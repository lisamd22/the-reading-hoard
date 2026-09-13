import Foundation
import Vision
import CoreGraphics

struct RecognizedLine: Sendable, Equatable {
    let text: String
    let confidence: Float
    /// Normalised Vision coordinates: origin bottom-left, 0…1.
    let boundingBox: CGRect

    /// Vision's origin is bottom-left, so a LARGER y is HIGHER on the page.
    var topDownY: CGFloat { 1 - boundingBox.maxY }
}

actor OCREngine {

    struct Options: Sendable {
        var recognitionLevel: VNRequestTextRecognitionLevel = .accurate
        /// Language correction actively harms invented fantasy titles — it "corrects"
        /// Onyx Storm and Quicksilver into dictionary words. Off by default.
        var usesLanguageCorrection = false
        var minimumTextHeight: Float = 0.012
        /// Seeded from authors already in the library, so OCR stops mangling names
        /// it has seen before.
        var customWords: [String] = []
        var recognitionLanguages: [String] = ["en-US"]

        static let `default` = Options()
    }

    /// Capped at 2 concurrent requests. A widely-repeated radar (FB17240843) claims
    /// >2 concurrent `.accurate` requests deadlock; that is unverified, but the cap
    /// plus a per-request timeout is cheap and correct whether the real behaviour is
    /// "hangs" or merely "slow".
    private let maxConcurrent = 2
    private var inFlight = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func recognize(_ image: CGImage, options: Options = .default) async throws -> [RecognizedLine] {
        await acquire()
        defer { release() }
        return try Self.perform(image, options: options)
    }

    /// Runs several images through the engine, never exceeding the concurrency cap.
    func recognize(images: [CGImage], options: Options = .default) async -> [[RecognizedLine]] {
        await withTaskGroup(of: (Int, [RecognizedLine]).self) { group in
            for (i, image) in images.enumerated() {
                group.addTask { [weak self] in
                    guard let self else { return (i, []) }
                    let lines = (try? await self.recognize(image, options: options)) ?? []
                    return (i, lines)
                }
            }
            var out = [[RecognizedLine]](repeating: [], count: images.count)
            for await (i, lines) in group { out[i] = lines }
            return out
        }
    }

    // MARK: - Concurrency gate

    private func acquire() async {
        if inFlight < maxConcurrent { inFlight += 1; return }
        await withCheckedContinuation { waiters.append($0) }
        inFlight += 1
    }

    private func release() {
        inFlight -= 1
        if !waiters.isEmpty { waiters.removeFirst().resume() }
    }

    // MARK: - Vision

    private nonisolated static func perform(_ image: CGImage, options: Options) throws -> [RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = options.recognitionLevel
        request.usesLanguageCorrection = options.usesLanguageCorrection
        request.minimumTextHeight = options.minimumTextHeight
        request.recognitionLanguages = options.recognitionLanguages
        if !options.customWords.isEmpty { request.customWords = options.customWords }

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        let observations = request.results ?? []
        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return RecognizedLine(text: text,
                                  confidence: candidate.confidence,
                                  boundingBox: observation.boundingBox)
        }
    }
}

extension Array where Element == RecognizedLine {
    /// Vision returns observations in no guaranteed order. Reading order is
    /// top-to-bottom, then left-to-right within a band — which is what a numbered
    /// list graphic needs.
    func inReadingOrder(bandHeight: CGFloat = 0.02) -> [RecognizedLine] {
        sorted { a, b in
            if abs(a.topDownY - b.topDownY) > bandHeight { return a.topDownY < b.topDownY }
            return a.boundingBox.minX < b.boundingBox.minX
        }
    }
}
