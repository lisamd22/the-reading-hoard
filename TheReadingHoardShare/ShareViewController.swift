import UIKit
import UniformTypeIdentifiers

/// The share extension is a courier. It finds the link, writes it to the App
/// Group inbox, POSTs it to the backend so work starts before the sheet even
/// dismisses, and gets out of the way. It never fetches, plays, or shows media.
///
/// Measured payloads (docs/probe-results/PAYLOAD-MATRIX.md): Instagram and
/// TikTok vend `public.url`; YouTube vends ONLY `public.plain-text` with the
/// bare URL inside; Pinterest vends both, with junk text and the URL second.
/// So: scan every attachment, prefer a URL, fall back to a data detector over
/// text, and never assume attachments[0].
@objc(ShareViewController)
final class ShareViewController: UIViewController {

    private let card = UIView()
    private let label = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var finished = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        buildUI()
        show("Taking the link to the library…", busy: true)
        Task { await handleShare() }
    }

    // MARK: - Flow

    private func handleShare() async {
        guard let url = await findURL() else {
            finish("The library reads Instagram, TikTok, YouTube and Pinterest links.", after: 1.6)
            return
        }
        let platform = ImportPlatform.detect(host: url.host)
        guard platform != .unknown, platform != .photos else {
            finish("The library reads Instagram, TikTok, YouTube and Pinterest links.", after: 1.6)
            return
        }

        // Write first, so a dead network or a jetsam kill still leaves the link
        // for the app to pick up.
        var pending = PendingImport(id: UUID().uuidString, url: url.absoluteString,
                                    platform: platform.rawValue, state: .submitted,
                                    jobID: nil, createdAt: Date())
        SharedImportInbox.upsert(pending)
        ImportTrace.write("share: wrote \(pending.id) \(url.absoluteString)")

        var api = HoardAPI.configured
        api = HoardAPI(baseURL: api.baseURL, appKey: api.appKey, installID: api.installID)
        do {
            let accepted = try await withTimeout(seconds: 2.5) { try await api.submit(url: url, clientJobID: pending.id) }
            pending.state = .queued
            pending.jobID = accepted.jobID
            pending.cached = accepted.cached
            SharedImportInbox.upsert(pending)
            ImportTrace.write("share: queued job=\(accepted.jobID) cached=\(accepted.cached)")
            finish(accepted.cached
                   ? "The library has read this one before. It's in My Library."
                   : "The library has the link. Come back when you're ready.", after: 1.2)
        } catch {
            // Left as .submitted; the app resubmits on next launch. Same calm line —
            // from the user's side nothing went wrong.
            ImportTrace.write("share: submit failed (\(error)) — left as submitted")
            finish("The library has the link. Come back when you're ready.", after: 1.2)
        }
    }

    /// Scan every attachment of every item. `public.url` wins; otherwise the
    /// first URL a data detector finds inside `public.plain-text`.
    private func findURL() async -> URL? {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        var textCandidates: [String] = []

        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let u = await load(provider, UTType.url.identifier) as? URL, u.host != nil {
                        return u
                    }
                    if let s = await load(provider, UTType.url.identifier) as? String, let u = URL(string: s), u.host != nil {
                        return u
                    }
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let s = await load(provider, UTType.plainText.identifier) as? String { textCandidates.append(s) }
                    else if let d = await load(provider, UTType.plainText.identifier) as? Data,
                            let s = String(data: d, encoding: .utf8) { textCandidates.append(s) }
                }
            }
            if let s = item.attributedContentText?.string { textCandidates.append(s) }
        }

        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        for text in textCandidates {
            let range = NSRange(text.startIndex..., in: text)
            if let match = detector?.firstMatch(in: text, options: [], range: range), let u = match.url, u.host != nil {
                return u
            }
        }
        return nil
    }

    private func load(_ provider: NSItemProvider, _ type: String) async -> Any? {
        await withCheckedContinuation { cont in
            var resumed = false
            let lock = NSLock()
            func once(_ v: Any?) { lock.lock(); defer { lock.unlock() }; if !resumed { resumed = true; cont.resume(returning: v) } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 4) { once(nil) }   // a stalled provider must not hang the sheet
            provider.loadItem(forTypeIdentifier: type, options: nil) { obj, _ in once(obj) }
        }
    }

    private func withTimeout<T>(seconds: Double, _ op: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await op() }
            group.addTask { try await Task.sleep(nanoseconds: UInt64(seconds * 1e9)); throw URLError(.timedOut) }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // MARK: - UI

    private func show(_ text: String, busy: Bool) {
        label.text = text
        busy ? spinner.startAnimating() : spinner.stopAnimating()
        spinner.isHidden = !busy
    }

    private func finish(_ text: String, after delay: Double) {
        guard !finished else { return }
        finished = true
        show(text, busy: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }

    private func buildUI() {
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = UIColor(red: 0.095, green: 0.075, blue: 0.12, alpha: 0.96)   // HoardTheme.midnight
        card.layer.cornerRadius = 20
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor(red: 0.79, green: 0.61, blue: 0.27, alpha: 0.24).cgColor  // gold
        view.addSubview(card)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = UIColor(red: 0.94, green: 0.88, blue: 0.74, alpha: 1)   // parchment
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = UIColor(red: 0.79, green: 0.61, blue: 0.27, alpha: 1)

        let stack = UIStackView(arrangedSubviews: [spinner, label])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .center
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.82),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
        ])
    }
}
