import Foundation

/// The library's durable home. Versioned Codable JSON written atomically.
///
/// Deliberately not SwiftData: the library is a single small array, the app has zero
/// dependencies, and a plain file gives us an explicit schema version and a corrupt-file
/// recovery path we control. Revisit if the library ever needs querying rather than loading.
actor LibraryStore {

    struct Envelope: Codable {
        var schemaVersion: Int
        var books: [BookRecommendation]
    }

    enum LoadOutcome: Equatable {
        case loaded(count: Int)
        case empty
        /// The file existed but could not be decoded. We start empty rather than
        /// crashing, and keep the bad file for inspection.
        case recovered(from: String)
    }

    private let fileURL: URL
    private var cache: [BookRecommendation]?

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Default location: Application Support, which is backed up and not user-visible.
    static func defaultURL(fileManager: FileManager = .default) -> URL {
        let base = (try? fileManager.url(for: .applicationSupportDirectory,
                                         in: .userDomainMask,
                                         appropriateFor: nil,
                                         create: true))
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("library.json")
    }

    // MARK: - Reading

    @discardableResult
    func load() -> LoadOutcome {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            cache = []
            return .empty
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let envelope = try Self.decoder.decode(Envelope.self, from: data)
            cache = envelope.books
            return .loaded(count: envelope.books.count)
        } catch {
            // Never let a bad file take the app down. Preserve it, start clean.
            let quarantine = fileURL.deletingLastPathComponent()
                .appendingPathComponent("library.corrupt.json")
            try? FileManager.default.removeItem(at: quarantine)
            try? FileManager.default.moveItem(at: fileURL, to: quarantine)
            cache = []
            return .recovered(from: error.localizedDescription)
        }
    }

    func books() -> [BookRecommendation] {
        if let cache { return cache }
        load()
        return cache ?? []
    }

    // MARK: - Writing

    /// Merge `incoming` into the stored library and persist. Returns the merge
    /// outcome so callers can surface ambiguous matches for user review.
    @discardableResult
    func add(_ incoming: [BookRecommendation]) throws -> MergeResult {
        let current = books()
        let result = RecommendationLibrary.merging(current: current, incoming: incoming)
        try persist(result.library)
        return result
    }

    @discardableResult
    func update(_ book: BookRecommendation) throws -> [BookRecommendation] {
        var all = books()
        guard let index = all.firstIndex(where: { $0.id == book.id }) else { return all }
        all[index] = book
        try persist(all)
        return all
    }

    @discardableResult
    func remove(id: UUID) throws -> [BookRecommendation] {
        let all = books().filter { $0.id != id }
        try persist(all)
        return all
    }

    func replaceAll(_ books: [BookRecommendation]) throws {
        try persist(books)
    }

    private func persist(_ books: [BookRecommendation]) throws {
        let envelope = Envelope(schemaVersion: BookRecommendation.schemaVersion, books: books)
        let data = try Self.encoder.encode(envelope)

        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Atomic: a crash mid-write leaves the previous file intact rather than a
        // truncated one.
        try data.write(to: fileURL, options: .atomic)
        cache = books
    }

    // MARK: - Coding

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
