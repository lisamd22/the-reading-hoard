import SwiftUI

struct ImportView: View {
    let importer: any RecommendationImporting
    let onImported: (BookRecommendation) -> Void

    @State private var urlText = ""
    @State private var phase: Phase = .idle

    private enum Phase: Equatable {
        case idle
        case importing
        case success(BookRecommendation)
        case failure(String)
    }

    var body: some View {
        ZStack {
            HoardTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("A NEW DISCOVERY")
                        .font(.caption.weight(.bold))
                        .tracking(2)
                        .foregroundStyle(HoardTheme.gold)
                    Text("Bring a Reel to the library.")
                        .font(HoardTheme.titleFont(34))
                        .foregroundStyle(HoardTheme.parchment)
                    Text("Paste an Instagram Reel link. We’ll find the book and preserve the reason it was recommended.")
                        .foregroundStyle(HoardTheme.mutedParchment)
                        .lineSpacing(4)

                    VStack(alignment: .leading, spacing: 14) {
                        Label("Instagram Reel", systemImage: "link")
                            .font(.headline)
                            .foregroundStyle(HoardTheme.parchment)

                        TextField("https://instagram.com/reel/…", text: $urlText)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .padding(14)
                            .foregroundStyle(HoardTheme.parchment)
                            .background(HoardTheme.ink.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(HoardTheme.gold.opacity(0.3))
                            }

                        Button(action: startImport) {
                            HStack {
                                if phase == .importing {
                                    ProgressView().tint(HoardTheme.ink)
                                } else {
                                    Image(systemName: "sparkles")
                                }
                                Text(phase == .importing ? "Reading the Reel…" : "Find the books")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundStyle(HoardTheme.ink)
                            .background(HoardTheme.gold, in: RoundedRectangle(cornerRadius: 13))
                        }
                        .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || phase == .importing)
                        .opacity(urlText.isEmpty ? 0.55 : 1)
                    }
                    .hoardCard()

                    resultView
                }
                .padding(20)
            }
        }
        .navigationTitle("Import")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(HoardTheme.ink.opacity(0.95), for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    @ViewBuilder
    private var resultView: some View {
        switch phase {
        case .idle, .importing:
            EmptyView()
        case .success(let recommendation):
            VStack(alignment: .leading, spacing: 12) {
                Label("Remembered", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(HoardTheme.gold)
                BookCard(recommendation: recommendation)
                Text("You’ll find this recommendation in My Library.")
                    .font(.footnote)
                    .foregroundStyle(HoardTheme.mutedParchment)
            }
        case .failure(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(HoardTheme.parchment)
                .hoardCard()
        }
    }

    private func startImport() {
        guard let url = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            phase = .failure(RecommendationImportError.unsupportedURL.localizedDescription)
            return
        }

        phase = .importing
        Task {
            do {
                let recommendation = try await importer.importRecommendation(from: url)
                onImported(recommendation)
                withAnimation { phase = .success(recommendation) }
            } catch {
                withAnimation { phase = .failure(error.localizedDescription) }
            }
        }
    }
}
