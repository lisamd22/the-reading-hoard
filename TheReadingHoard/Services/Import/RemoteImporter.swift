import Foundation
import os

private let log = Logger(subsystem: "com.lisamd22.TheReadingHoard", category: "import")


/// What the Import screen listens to. One stream per link.
enum ImportEvent: Sendable {
    case queued(jobID: String, cached: Bool)
    case stage(String)
    case captionNames(count: Int)
    /// A book the server grounded, resolved against Apple Books on this device.
    case book(BookRecommendation)
    case done(count: Int, message: String)
    case failed(message: String, partialCount: Int)
}

/// The link path: POST the URL, stream the server's grounded books, resolve each
/// against Apple Books here, hand back `BookRecommendation`s as they land.
struct RemoteImporter: Sendable {
    var api: HoardAPI = .configured
    var catalog: any CatalogResolving = AppleBooksCatalog()

    func run(url: URL, clientJobID: String = UUID().uuidString) -> AsyncStream<ImportEvent> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    let accepted = try await api.submit(url: url, clientJobID: clientJobID)
                    log.info("submitted job=\(accepted.jobID, privacy: .public) cached=\(accepted.cached)"); ImportTrace.write("submitted \(accepted.jobID) cached=\(accepted.cached)")
                    continuation.yield(.queued(jobID: accepted.jobID, cached: accepted.cached))
                    for await ev in stream(jobID: accepted.jobID) { continuation.yield(ev) }
                } catch {
                    log.error("stream error: \(error.localizedDescription, privacy: .public)"); ImportTrace.write("ERROR \(error)")
                    continuation.yield(.failed(message: error.localizedDescription, partialCount: 0))
                }
                log.info("stream finished"); ImportTrace.write("finished")
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Resume a job the share extension already submitted. Replays from the
    /// server's event log, so a job that finished while the app was closed lands
    /// in ~0.4 s.
    func resume(jobID: String) -> AsyncStream<ImportEvent> { stream(jobID: jobID) }

    private func stream(jobID: String) -> AsyncStream<ImportEvent> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    var count = 0
                    for try await event in api.events(jobID: jobID) {
                        log.info("event: \(String(describing: event).prefix(80), privacy: .public)"); ImportTrace.write("event \(String(describing: event).prefix(100))")
                        switch event {
                        case .accepted(let cached, let message):
                            if let message { continuation.yield(.stage(message)) }
                            _ = cached
                        case .caption(let spans, _):
                            continuation.yield(.captionNames(count: spans.count))
                        case .stage(_, let message):
                            continuation.yield(.stage(message))
                        case .book(let remote):
                            ImportTrace.write("resolving \(remote.title)")
                            let rec = await resolve(remote)
                            ImportTrace.write("resolved \(rec.title) -> \(rec.resolution.rawValue)")
                            count += 1
                            continuation.yield(.book(rec))
                        case .done(let n, let message, _):
                            continuation.yield(.done(count: max(n, count), message: message))
                        case .failed(let code, let message, let partial):
                            _ = code
                            continuation.yield(.failed(message: message, partialCount: partial))
                        }
                    }
                } catch {
                    log.error("stream error: \(error.localizedDescription, privacy: .public)"); ImportTrace.write("ERROR \(error)")
                    continuation.yield(.failed(message: error.localizedDescription, partialCount: 0))
                }
                log.info("stream finished"); ImportTrace.write("finished")
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Server book -> library record. The server is the witness; Apple Books is
    /// the librarian. If the catalog has nothing, the book is still kept, marked
    /// unresolved, with the verbatim title and its evidence intact.
    private func resolve(_ remote: RemoteBook) async -> BookRecommendation {
        let source = ImportSource(
            platform: ImportPlatform(rawValue: remote.source.platform) ?? .unknown,
            itemID: remote.source.itemID,
            canonicalURL: remote.source.canonicalURL.flatMap(URL.init(string:)),
            creatorHandle: remote.source.creatorHandle
        )
        let evidence = remote.evidence.map {
            EvidenceSpan(id: $0.id,
                         channel: EvidenceSpan.Channel(rawValue: $0.channel) ?? .onScreenText,
                         text: $0.text,
                         startSeconds: $0.startSeconds)
        }
        let summary = Self.summary(remote, source: source)

        let match = (try? await catalog.resolve(title: remote.title, author: remote.authorHint))?.best
        if let match, match.score >= CatalogScorer.reviewFloor {
            return BookRecommendation(
                title: match.title,
                author: match.authors.first ?? remote.authorHint,
                recommendationSummary: summary,
                sources: [source],
                evidence: evidence,
                confidence: match.score >= CatalogScorer.autoAcceptFloor ? .high : .medium,
                resolution: CatalogScorer.resolution(for: match.score),
                appleTrackID: match.appleTrackID,
                appleStoreURL: match.appleStoreURL,
                coverURL: match.coverURL,
                genres: match.genres
            )
        }
        return BookRecommendation(
            title: remote.title,
            author: remote.authorHint,
            recommendationSummary: summary,
            sources: [source],
            evidence: evidence,
            confidence: remote.confidence == "high" ? .medium : .low,
            resolution: .unresolved
        )
    }

    /// Until the LLM writes summaries, the "why" is the evidence itself — a quote
    /// with a place in the video. Unhallucinatable by construction.
    private static func summary(_ remote: RemoteBook, source: ImportSource) -> String {
        guard let first = remote.evidence.first else { return "Found in a \(source.platform.displayName) post." }
        // A timestamp of zero means a still image or the caption, not "at 0:00".
        let at = first.startSeconds.flatMap { $0 > 0 ? String(format: " at %d:%02d", Int($0) / 60, Int($0) % 60) : nil } ?? ""
        let how: String
        switch first.modality {
        case "spoken":         how = "Spoken\(at)"
        case "cover_visible":  how = "On the cover\(at)"
        case "on_screen_text": how = "On screen\(at)"
        case "caption":        how = "Named in the caption"
        case "comment":        how = "Named in the comments"
        default:               how = "Seen\(at)"
        }
        let by = source.creatorHandle.map { " by @\($0)" } ?? ""
        return "\(how) in a \(source.platform.displayName) post\(by): “\(first.text)”"
    }
}
