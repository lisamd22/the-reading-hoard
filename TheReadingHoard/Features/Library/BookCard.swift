import SwiftUI

struct BookCard: View {
    let recommendation: BookRecommendation

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            cover
                .frame(width: 72, height: 106)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 7) {
                Text(recommendation.status.rawValue.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(1.3)
                    .foregroundStyle(HoardTheme.gold)
                Text(recommendation.title)
                    .font(.headline)
                    .foregroundStyle(HoardTheme.parchment)
                Text(recommendation.displayAuthor)
                    .font(.subheadline)
                    .foregroundStyle(HoardTheme.mutedParchment)
                Text(recommendation.recommendationSummary)
                    .font(.subheadline)
                    .foregroundStyle(HoardTheme.parchment.opacity(0.9))
                    .lineLimit(3)
                    .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hoardCard()
        .accessibilityElement(children: .combine)
    }

    /// Apple Books artwork (400x400bb.webp, ~27 KB) with the gradient placeholder
    /// while it loads or when there is none. URLCache keeps repeats free.
    @ViewBuilder
    private var cover: some View {
        if let url = recommendation.coverURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(LinearGradient(colors: [HoardTheme.ember, HoardTheme.plum],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay { Image(systemName: "book.closed.fill").foregroundStyle(HoardTheme.gold.opacity(0.9)) }
    }
}
