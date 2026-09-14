import Foundation

/// Everything the app and the share extension share: one App Group container,
/// one UserDefaults suite, one trace file. Both targets compile this file.
enum AppGroup {
    static let id = "group.com.lisamd22.TheReadingHoard"

    /// Shared defaults. `UserDefaults.standard` is per-process, so an install id
    /// minted by the app would be invisible to the extension without this.
    static let defaults: UserDefaults = UserDefaults(suiteName: id) ?? .standard

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }

    /// Stable per-install id for rate limiting. Not an account, not cross-install
    /// tracking; a reinstall mints a new one.
    static var installID: String {
        let key = "HoardInstallID"
        if let id = defaults.string(forKey: key) { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: key)
        return id
    }
}

/// Dev trace that survives the Simulator's unreliable unified log. Writes to the
/// App Group so the app can read what the extension did. DEBUG builds only.
enum ImportTrace {
    static var url: URL {
        (AppGroup.containerURL ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("import-trace.log")
    }
    static func write(_ line: String) {
        #if DEBUG
        let stamped = "\(Date().timeIntervalSince1970.rounded(.down)) \(line)\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(stamped.data(using: .utf8)!); try? h.close()
        } else {
            try? stamped.write(to: url, atomically: true, encoding: .utf8)
        }
        #endif
    }
}
