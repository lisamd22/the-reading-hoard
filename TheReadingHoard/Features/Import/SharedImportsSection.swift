import SwiftUI

/// What happened to each link the share extension handed over. A failure is
/// never silent: the user sees the link, the reason, and a way to try again.
struct SharedImportsSection: View {
    @EnvironmentObject private var appState: AppState
    /// Library shows only what needs attention; Import shows recent history too.
    var onlyUnfinished = false

    private var items: [PendingImport] {
        appState.sharedImports.filter { onlyUnfinished ? $0.state != .done : ($0.state != .done || isRecent($0)) }
    }

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("Shared with the library", systemImage: "square.and.arrow.down")
                    .font(.headline)
                    .foregroundStyle(HoardTheme.parchment)
                ForEach(items) { item in
                    row(item)
                }
            }
            .hoardCard()
        }
    }

    private func row(_ item: PendingImport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text((ImportPlatform(rawValue: item.platform) ?? .unknown).displayName)
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(HoardTheme.gold)
                Spacer()
                Text(item.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(HoardTheme.mutedParchment)
            }
            Text(shortURL(item.url))
                .font(.footnote.monospaced())
                .foregroundStyle(HoardTheme.mutedParchment)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 8) {
                statusIcon(item.state)
                Text(statusText(item))
                    .font(.subheadline)
                    .foregroundStyle(HoardTheme.parchment.opacity(0.9))
                    .lineSpacing(2)
            }
            if item.state == .failed {
                HStack(spacing: 12) {
                    Button("Try again") { appState.retrySharedImport(id: item.id) }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HoardTheme.gold)
                    Button("Forget it") { appState.dismissSharedImport(id: item.id) }
                        .font(.subheadline)
                        .foregroundStyle(HoardTheme.mutedParchment)
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusIcon(_ state: PendingImport.State) -> some View {
        switch state {
        case .submitted, .queued: ProgressView().tint(HoardTheme.gold).controlSize(.small)
        case .done: Image(systemName: "checkmark.seal.fill").foregroundStyle(HoardTheme.gold)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(HoardTheme.ember)
        }
    }

    private func statusText(_ item: PendingImport) -> String {
        switch item.state {
        case .submitted: return "Taking the link to the library."
        case .queued: return item.cached ? "The library has read this one before." : "Watching, and listening."
        case .done: return item.message ?? "Remembered."
        case .failed: return item.message ?? "The library couldn't read this one."
        }
    }

    private func isRecent(_ item: PendingImport) -> Bool {
        Date().timeIntervalSince(item.createdAt) < 600
    }

    private func shortURL(_ s: String) -> String {
        s.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "www.", with: "")
    }
}
