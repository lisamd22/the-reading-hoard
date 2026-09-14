import Foundation
import os

private let apiLog = Logger(subsystem: "com.lisamd22.TheReadingHoard", category: "api")

/// The one backend. A URL goes up, books come back as a stream of events.
/// The app never fetches from Instagram, TikTok, YouTube or Pinterest itself.
struct HoardAPI: Sendable {
    let baseURL: URL
    let appKey: String
    let installID: String

    /// Dev override: `-hoard-api http://192.168.1.10:8080` as a launch argument
    /// (the app persists it to the App Group so the extension uses it too), or
    /// the `HoardAPIBaseURL` key in the shared defaults. Falls back to the
    /// production host. The Simulator can reach the Mac at localhost.
    static var configured: HoardAPI {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-hoard-api"), i + 1 < args.count {
            AppGroup.defaults.set(args[i + 1], forKey: "HoardAPIBaseURL")
        }
        let base = AppGroup.defaults.string(forKey: "HoardAPIBaseURL")
        #if targetEnvironment(simulator)
        let fallback = "http://localhost:8080"
        #else
        let fallback = "https://hoard-api.fly.dev"
        #endif
        return HoardAPI(
            baseURL: URL(string: base ?? fallback)!,
            appKey: (Bundle.main.object(forInfoDictionaryKey: "HoardAppKey") as? String) ?? "",
            installID: AppGroup.installID
        )
    }

    struct JobAccepted: Decodable, Sendable {
        let jobID: String
        let platform: String
        let canonicalID: String?
        let cached: Bool
    }

    enum APIError: LocalizedError {
        case unsupportedLink
        case dailyLimit
        case unauthorized
        case server(Int)
        case unreachable

        var errorDescription: String? {
            switch self {
            case .unsupportedLink: return "The library doesn't recognise that link. It reads Instagram, TikTok, YouTube and Pinterest."
            case .dailyLimit: return "The library has read a great deal today. It will pick this up tomorrow."
            case .unauthorized: return "The library couldn't verify this copy of the app."
            case .server(let code): return "The library couldn't be reached (\(code))."
            case .unreachable: return "The library is out of reach right now. It has kept the link."
            }
        }
    }

    // MARK: - Submit

    func submit(url: URL, clientJobID: String) async throws -> JobAccepted {
        var req = URLRequest(url: baseURL.appendingPathComponent("v1/jobs"))
        req.httpMethod = "POST"
        req.timeoutInterval = 8
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(installID, forHTTPHeaderField: "X-Install-ID")
        if !appKey.isEmpty { req.setValue(appKey, forHTTPHeaderField: "X-App-Key") }
        let body: [String: Any] = [
            "url": url.absoluteString,
            "clientJobID": clientJobID,
            "storefront": Locale.current.region?.identifier ?? "US",
            "locale": Locale.current.identifier,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do { (data, response) = try await URLSession.shared.data(for: req) }
        catch { throw APIError.unreachable }
        guard let http = response as? HTTPURLResponse else { throw APIError.unreachable }
        switch http.statusCode {
        case 202: return try JSONDecoder().decode(JobAccepted.self, from: data)
        case 422: throw APIError.unsupportedLink
        case 429: throw APIError.dailyLimit
        case 401: throw APIError.unauthorized
        default: throw APIError.server(http.statusCode)
        }
    }

    // MARK: - Events

    /// Server-sent events for a job. Replays from `lastEventID` if reconnecting.
    /// Ends after `done` or `failed`. No dependencies: URLSession.bytes + .lines.
    func events(jobID: String, lastEventID: Int? = nil) -> AsyncThrowingStream<ServerEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var req = URLRequest(url: baseURL.appendingPathComponent("v1/jobs/\(jobID)/events"))
                req.timeoutInterval = 180
                req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                if let lastEventID { req.setValue(String(lastEventID), forHTTPHeaderField: "Last-Event-ID") }
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                        throw APIError.server((response as? HTTPURLResponse)?.statusCode ?? 0)
                    }
                    apiLog.info("events: connected status=\((response as? HTTPURLResponse)?.statusCode ?? -1)"); ImportTrace.write("events connected \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                    // URLSession's `.lines` DROPS blank lines (measured 2026-09-13), so the
                    // SSE record separator never arrives. Dispatch when the next record
                    // starts (an `id:` or `event:` after a complete record) and at end of
                    // stream, never on the blank line alone.
                    var id: Int?
                    var event = ""
                    var data = ""
                    var lineCount = 0
                    var terminated = false

                    func dispatch() -> Bool {
                        guard !event.isEmpty, !data.isEmpty else { return false }
                        defer { id = nil; event = ""; data = "" }
                        if let ev = ServerEvent(id: id, type: event, json: data) {
                            continuation.yield(ev)
                            return ev.isTerminal
                        }
                        ImportTrace.write("PARSE FAIL type=\(event) data=\(data.prefix(150))")
                        return false
                    }

                    for try await line in bytes.lines {
                        lineCount += 1
                        if lineCount <= 8 { ImportTrace.write("line\(lineCount) [\(line.prefix(70))]") }
                        if line.isEmpty || line.hasPrefix(":") {
                            if line.isEmpty, dispatch() { terminated = true; break }
                            continue
                        }
                        if line.hasPrefix("id: ") {
                            if dispatch() { terminated = true; break }
                            id = Int(line.dropFirst(4))
                        } else if line.hasPrefix("event: ") {
                            if !data.isEmpty, dispatch() { terminated = true; break }
                            event = String(line.dropFirst(7))
                        } else if line.hasPrefix("data: ") {
                            data += String(line.dropFirst(6))
                        }
                    }
                    if !terminated { _ = dispatch() }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// One event off the wire. Mirrors backend/app/jobs.py.
enum ServerEvent: Sendable {
    case accepted(cached: Bool, message: String?)
    case caption(spans: [String: String], degraded: Bool)
    case stage(String, message: String)
    case book(RemoteBook)
    case done(count: Int, message: String, cached: Bool)
    case failed(code: String, message: String, partialCount: Int)

    var id: Int? {
        switch self { default: return nil }
    }

    var isTerminal: Bool {
        switch self {
        case .done, .failed: return true
        default: return false
        }
    }

    init?(id: Int?, type: String, json: String) {
        guard let data = json.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        switch type {
        case "accepted":
            self = .accepted(cached: obj["cached"] as? Bool ?? false, message: obj["message"] as? String)
        case "caption":
            self = .caption(spans: obj["spans"] as? [String: String] ?? [:], degraded: obj["degraded"] as? Bool ?? false)
        case "media.fetching", "media.reading":
            self = .stage(type, message: obj["message"] as? String ?? "")
        case "book":
            guard let book = try? JSONDecoder().decode(RemoteBook.self, from: data) else { return nil }
            self = .book(book)
        case "done":
            self = .done(count: obj["count"] as? Int ?? 0, message: obj["message"] as? String ?? "",
                         cached: obj["cached"] as? Bool ?? false)
        case "failed":
            self = .failed(code: obj["code"] as? String ?? "unknown",
                           message: obj["userMessage"] as? String ?? "The library couldn't read this one.",
                           partialCount: obj["partialCount"] as? Int ?? 0)
        default:
            return nil
        }
    }
}

/// A grounded book as the server emits it. `authorHint` is exactly that — the
/// author shown in the app always comes from the Apple Books record.
struct RemoteBook: Decodable, Sendable, Equatable {
    struct Evidence: Decodable, Sendable, Equatable {
        let id: String
        let channel: String
        let text: String
        let startSeconds: Double?
        let modality: String
    }
    struct Source: Decodable, Sendable, Equatable {
        let platform: String
        let itemID: String?
        let canonicalURL: String?
        let creatorHandle: String?
    }
    let title: String
    let authorHint: String?
    let series: String?
    let confidence: String
    let isRecommended: Bool
    let legibilityNote: String?
    let evidence: [Evidence]
    let source: Source
}
