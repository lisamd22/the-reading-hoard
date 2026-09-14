import SwiftUI
import PhotosUI
import ImageIO

struct ImportView: View {
    var remote = RemoteImporter()
    let onImported: ([BookRecommendation]) -> Void
    var customWords: [String] = []

    @State private var urlText = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var phase: Phase = .idle
    @State private var streamTask: Task<Void, Never>?

    private enum Phase: Equatable {
        case idle
        case working(String)
        /// Books arriving one by one while the server is still watching.
        case streaming([BookRecommendation], stage: String)
        case found([BookRecommendation], message: String)
        case nothingFound(String)
        case failure(String, partial: [BookRecommendation])
    }

    private var isWorking: Bool {
        switch phase {
        case .working, .streaming: return true
        default: return false
        }
    }

    var body: some View {
        ZStack {
            HoardTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    linkCard
                    resultView
                    SharedImportsSection()
                    screenshotCard
                }
                .padding(20)
            }
        }
        .navigationTitle("Import")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(HoardTheme.ink.opacity(0.95), for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await readScreenshot(item) }
        }
        .onAppear(perform: honourLaunchArgument)
        // No cancel on disappear: TabView fires onDisappear during initial layout,
        // which killed the stream silently. The stream ends itself on done/failed;
        // starting a new import cancels the previous one.
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("A NEW DISCOVERY")
                .font(.caption.weight(.bold))
                .tracking(2)
                .foregroundStyle(HoardTheme.gold)
            Text("Bring a video to the library.")
                .font(HoardTheme.titleFont(34))
                .foregroundStyle(HoardTheme.parchment)
            Text("Share or paste a link from Instagram, TikTok, YouTube or Pinterest. The library watches the video and remembers every book it sees or hears.")
                .foregroundStyle(HoardTheme.mutedParchment)
                .lineSpacing(4)
        }
    }

    // MARK: - Link (hero)

    private var linkCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Link", systemImage: "link")
                .font(.headline)
                .foregroundStyle(HoardTheme.parchment)

            TextField("https://…", text: $urlText)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit(startLinkImport)
                .padding(14)
                .foregroundStyle(HoardTheme.parchment)
                .background(HoardTheme.ink.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).stroke(HoardTheme.gold.opacity(0.3)) }

            if let hint = linkHint {
                Text(hint).font(.footnote).foregroundStyle(HoardTheme.mutedParchment).lineSpacing(3)
            }

            Button(action: startLinkImport) {
                HStack {
                    if isWorking { ProgressView().tint(HoardTheme.ink) } else { Image(systemName: "sparkles") }
                    Text(isWorking ? "Watching…" : "Find the books")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(HoardTheme.ink)
                .background(HoardTheme.gold, in: RoundedRectangle(cornerRadius: 13))
            }
            .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
            .opacity(urlText.isEmpty ? 0.55 : 1)
        }
        .hoardCard()
    }

    /// Live, honest per-platform note. Every line reflects a measurement.
    private var linkHint: String? {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 8, let url = URL(string: trimmed) else { return nil }
        switch ImportPlatform.detect(host: url.host) {
        case .instagram: return "Instagram reels take a little longer — the library fetches the whole film."
        case .tiktok:    return "TikTok videos and photo posts both read well."
        case .youtube:   return "YouTube reads quickly. The library never downloads the video."
        case .pinterest: return "Pinterest video and image pins both read well."
        case .photos, .unknown: return "The library doesn't recognise that link yet. It reads Instagram, TikTok, YouTube and Pinterest."
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var resultView: some View {
        switch phase {
        case .idle:
            EmptyView()

        case .working(let stage):
            stageLine(stage)

        case .streaming(let books, let stage):
            VStack(alignment: .leading, spacing: 12) {
                stageLine(stage)
                ForEach(books) { BookCard(recommendation: $0).transition(.move(edge: .bottom).combined(with: .opacity)) }
            }

        case .found(let books, let message):
            VStack(alignment: .leading, spacing: 12) {
                Label(message, systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(HoardTheme.gold)
                ForEach(books) { BookCard(recommendation: $0) }
                if !books.isEmpty {
                    Text("You'll find these in My Library.")
                        .font(.footnote)
                        .foregroundStyle(HoardTheme.mutedParchment)
                }
            }

        case .nothingFound(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label("No books found", systemImage: "book.closed")
                    .font(.headline)
                    .foregroundStyle(HoardTheme.parchment)
                Text(message).font(.footnote).foregroundStyle(HoardTheme.mutedParchment)
            }
            .hoardCard()

        case .failure(let message, let partial):
            VStack(alignment: .leading, spacing: 12) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(HoardTheme.parchment)
                ForEach(partial) { BookCard(recommendation: $0) }
            }
            .hoardCard()
        }
    }

    private func stageLine(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().tint(HoardTheme.gold)
            Text(text).font(.subheadline).foregroundStyle(HoardTheme.mutedParchment)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Screenshot (fallback)

    private var screenshotCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Or a screenshot", systemImage: "photo.on.rectangle.angled")
                .font(.headline)
                .foregroundStyle(HoardTheme.parchment)
            Text("If a link can't be reached, a screenshot of the list reads just as well.")
                .font(.footnote)
                .foregroundStyle(HoardTheme.mutedParchment)
            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                Text("Choose a screenshot")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(HoardTheme.parchment)
                    .overlay { RoundedRectangle(cornerRadius: 12).stroke(HoardTheme.gold.opacity(0.45)) }
            }
            .disabled(isWorking)
        }
        .hoardCard()
    }

    // MARK: - Actions

    /// Dev: `-hoard-import <url>` pre-fills the field and starts the import, so
    /// the whole link path can be exercised on the Simulator without typing.
    private func honourLaunchArgument() {
        let args = ProcessInfo.processInfo.arguments
        guard case .idle = phase, urlText.isEmpty,
              let i = args.firstIndex(of: "-hoard-import"), i + 1 < args.count else { return }
        urlText = args[i + 1]
        startLinkImport()
    }

    private func startLinkImport() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isWorking else { return }
        guard let url = URL(string: trimmed), url.host != nil else {
            phase = .failure("That doesn't look like a link.", partial: [])
            return
        }
        streamTask?.cancel()
        phase = .working("The library has the link.")
        var books: [BookRecommendation] = []

        // @MainActor: every phase mutation below must land on the main thread, or
        // SwiftUI never observes it and the screen freezes on the first message.
        streamTask = Task { @MainActor in
            for await event in remote.run(url: url) {
                guard !Task.isCancelled else { return }
                switch event {
                case .queued(_, let cached):
                    if cached { phase = .working("The library has read this one before.") }
                case .stage(let message):
                    phase = books.isEmpty ? .working(message) : .streaming(books, stage: message)
                case .captionNames(let n):
                    if n > 0, books.isEmpty { phase = .working("Reading the caption, then the film.") }
                case .book(let rec):
                    books.append(rec)
                    onImported([rec])
                    withAnimation(.easeOut(duration: 0.35)) { phase = .streaming(books, stage: "Watching, and listening.") }
                case .done(let n, let message):
                    withAnimation {
                        phase = n == 0
                            ? .nothingFound(message)
                            : .found(books, message: message)
                    }
                case .failed(let message, _):
                    withAnimation { phase = .failure(message, partial: books) }
                }
            }
        }
    }

    private func readScreenshot(_ item: PhotosPickerItem) async {
        phase = .working("Opening the picture…")
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let src = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
                phase = .failure("That picture couldn't be opened.", partial: []); return
            }
            let outcome = try await ScreenshotImporter().run(
                image: image, source: ImportSource(platform: .photos), customWords: customWords
            ) { stage in Task { @MainActor in phase = .working(stage.label + "…") } }
            if outcome.books.isEmpty {
                withAnimation { phase = .nothingFound(outcome.ocrLineCount == 0
                    ? "The library couldn't read any words in that picture."
                    : "The library read \(outcome.ocrLineCount) lines but recognised no book titles among them.") }
            } else {
                onImported(outcome.books)
                withAnimation { phase = .found(outcome.books, message: outcome.books.count == 1 ? "One book remembered" : "\(outcome.books.count) books remembered") }
            }
        } catch {
            phase = .failure(error.localizedDescription, partial: [])
        }
        pickerItem = nil
    }
}
