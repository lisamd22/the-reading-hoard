import Foundation

/// A share the extension accepted. The extension writes it before it POSTs, so
/// nothing is lost if the network or the process dies; the app reconciles on
/// its next foreground.
struct PendingImport: Codable, Identifiable, Equatable, Sendable {
    enum State: String, Codable, Sendable {
        /// Written to disk; the POST has not succeeded yet. App resubmits.
        case submitted
        /// Backend returned 202; `jobID` is set. App streams the events.
        case queued
        /// Streamed to completion and adopted into the library.
        case done
        case failed
    }

    let id: String            // clientJobID — idempotency key on the backend
    let url: String
    let platform: String
    var state: State
    var jobID: String?
    var createdAt: Date
    var cached: Bool = false
    var message: String?
}

/// The App Group inbox. A single JSON file; both processes read and write it
/// under a file coordinator so a share landing mid-drain is not lost.
enum SharedImportInbox {
    private static var fileURL: URL? {
        AppGroup.containerURL?.appendingPathComponent("pending-imports.json")
    }

    static func load() -> [PendingImport] {
        guard let url = fileURL else { return [] }
        var result: [PendingImport] = []
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: [], error: nil) { u in
            if let data = try? Data(contentsOf: u),
               let items = try? decoder.decode([PendingImport].self, from: data) {
                result = items
            }
        }
        return result
    }

    static func upsert(_ item: PendingImport) {
        mutate { items in
            if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = item } else { items.append(item) }
        }
    }

    static func update(id: String, _ change: (inout PendingImport) -> Void) {
        mutate { items in
            if let i = items.firstIndex(where: { $0.id == id }) { change(&items[i]) }
        }
    }

    /// Drop finished entries older than a day so the file stays small.
    static func prune(olderThan interval: TimeInterval = 86_400) {
        mutate { items in
            items.removeAll { ($0.state == .done || $0.state == .failed) && Date().timeIntervalSince($0.createdAt) > interval }
        }
    }

    private static func mutate(_ change: (inout [PendingImport]) -> Void) {
        guard let url = fileURL else { return }
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: url, options: [], error: nil) { u in
            var items: [PendingImport] = []
            if let data = try? Data(contentsOf: u) { items = (try? decoder.decode([PendingImport].self, from: data)) ?? [] }
            change(&items)
            if let data = try? encoder.encode(items) { try? data.write(to: u, options: .atomic) }
        }
    }

    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
}
