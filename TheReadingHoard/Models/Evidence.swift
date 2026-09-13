import Foundation

/// A numbered, addressable span of source text. The LLM cites these IDs, and the
/// device re-verifies every citation against its own copy of the bundle — so a
/// hallucinated title would have to hallucinate a span ID *and* have that real
/// span's text contain the invented title's tokens. That is a property, not a hope.
struct EvidenceSpan: Identifiable, Codable, Hashable, Sendable {
    enum Channel: String, Codable, Sendable {
        case caption          // platform caption, YouTube description, video title
        case onScreenText     // Vision OCR — strongest signal on BookTok and Pinterest
        case spokenAudio      // on-device speech recognition
        case userProvided     // typed or pasted by the human

        var label: String {
            switch self {
            case .caption:      return "From the caption"
            case .onScreenText: return "On screen"
            case .spokenAudio:  return "Spoken"
            case .userProvided: return "You added this"
            }
        }
    }

    /// Short and stable — "c0", "o3", "t7", "u1". This is what the model cites.
    let id: String
    let channel: Channel
    let text: String
    /// Seconds into the media. nil for captions and stills.
    let startSeconds: Double?
    /// 0…1 from Vision or Speech, when the engine reports one.
    let engineConfidence: Double?

    init(id: String,
         channel: Channel,
         text: String,
         startSeconds: Double? = nil,
         engineConfidence: Double? = nil) {
        self.id = id
        self.channel = channel
        self.text = text
        self.startSeconds = startSeconds
        self.engineConfidence = engineConfidence
    }
}

/// Everything we gathered from one import, in citable form.
struct EvidenceBundle: Codable, Sendable {
    let source: ImportSource
    private(set) var spans: [EvidenceSpan]
    var mediaDurationSeconds: Double?
    var languageHint: String?

    init(source: ImportSource,
         spans: [EvidenceSpan] = [],
         mediaDurationSeconds: Double? = nil,
         languageHint: String? = nil) {
        self.source = source
        self.spans = spans
        self.mediaDurationSeconds = mediaDurationSeconds
        self.languageHint = languageHint
    }

    func span(_ id: EvidenceSpan.ID) -> EvidenceSpan? { spans.first { $0.id == id } }

    mutating func append(_ new: [EvidenceSpan]) {
        let known = Set(spans.map(\.id))
        spans.append(contentsOf: new.filter { !known.contains($0.id) })
    }

    /// Byte-identical to what the backend renders into the prompt, so the device
    /// can re-verify grounding against its own copy.
    func promptRendering() -> String {
        spans.map { span in
            let stamp = span.startSeconds.map { String(format: " %02d:%02d", Int($0) / 60, Int($0) % 60) } ?? ""
            return "[\(span.id)] \(span.channel.rawValue)\(stamp): \(span.text)"
        }.joined(separator: "\n")
    }
}
