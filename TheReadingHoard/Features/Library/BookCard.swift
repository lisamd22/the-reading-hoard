import SwiftUI

struct BookCard: View {
    let recommendation: BookRecommendation

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [HoardTheme.ember, HoardTheme.plum],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 72, height: 106)
                .overlay {
                    Image(systemName: "book.closed.fill")
                        .foregroundStyle(HoardTheme.gold.opacity(0.9))
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 7) {
                Text(recommendation.status.rawValue.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(1.3)
                    .foregroundStyle(HoardTheme.gold)
                Text(recommendation.title)
                    .font(.headline)
                    .foregroundStyle(HoardTheme.parchment)
                Text(recommendation.author)
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
}
