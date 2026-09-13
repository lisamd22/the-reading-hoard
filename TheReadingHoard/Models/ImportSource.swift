import Foundation

enum ImportPlatform: String, Codable, Sendable, CaseIterable {
    case instagram, tiktok, youtube, pinterest, photos, unknown

    var displayName: String {
        switch self {
        case .instagram: return "Instagram"
        case .tiktok:    return "TikTok"
        case .youtube:   return "YouTube"
        case .pinterest: return "Pinterest"
        case .photos:    return "Photos"
        case .unknown:   return "a link"
        }
    }

    /// Suffix matching, never exact — this covers www/m/vm/vt and every localised
    /// host (fr.pinterest.com, m.youtube.com) plus future short-link domains
    /// without a code change.
    static func detect(host rawHost: String?) -> ImportPlatform {
        guard let h = rawHost?.lowercased() else { return .unknown }
        func matches(_ domains: [String]) -> Bool {
            domains.contains { h == $0 || h.hasSuffix("." + $0) }
        }
        if matches(["instagram.com", "instagr.am"]) { return .instagram }
        if matches(["tiktok.com"]) { return .tiktok }
        if matches(["youtube.com", "youtu.be", "youtube-nocookie.com"]) { return .youtube }
        if matches(["pinterest.com", "pin.it"]) { return .pinterest }
        return .unknown
    }
}

/// Where a recommendation came from. A book can accumulate several of these —
/// "recommended in 3 reels" is a fact worth keeping, and the old single
/// `sourceURL` threw it away.
struct ImportSource: Codable, Hashable, Sendable, Identifiable {
    var platform: ImportPlatform
    /// IG shortcode, YouTube 11-char id, Pinterest numeric pin id.
    /// Deliberately nil for TikTok `vm.`/`vt.` short links, which genuinely
    /// contain no id — do not try to parse one out.
    var itemID: String?
    var canonicalURL: URL?
    var originalURL: URL?
    var creatorHandle: String?
    var capturedAt: Date

    init(platform: ImportPlatform,
         itemID: String? = nil,
         canonicalURL: URL? = nil,
         originalURL: URL? = nil,
         creatorHandle: String? = nil,
         capturedAt: Date = .now) {
        self.platform = platform
        self.itemID = itemID
        self.canonicalURL = canonicalURL
        self.originalURL = originalURL
        self.creatorHandle = creatorHandle
        self.capturedAt = capturedAt
    }

    var id: String {
        if let itemID { return "\(platform.rawValue):\(itemID)" }
        if let canonicalURL { return "\(platform.rawValue):\(canonicalURL.absoluteString)" }
        return "\(platform.rawValue):\(capturedAt.timeIntervalSince1970)"
    }
}
