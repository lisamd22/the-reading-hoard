import SwiftUI

struct LibraryView: View {
    let recommendations: [BookRecommendation]

    var body: some View {
        ZStack {
            HoardTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    libraryHeader

                    if recommendations.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 14) {
                            ForEach(recommendations) { recommendation in
                                BookCard(recommendation: recommendation)
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("My Library")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(HoardTheme.ink.opacity(0.95), for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var libraryHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("THE KEEPER'S COLLECTION")
                .font(.caption.weight(.bold))
                .tracking(2)
                .foregroundStyle(HoardTheme.gold)
            Text(recommendations.isEmpty ? "Your shelves are ready." : "\(recommendations.count) stor\(recommendations.count == 1 ? "y" : "ies") remembered")
                .font(HoardTheme.titleFont(30))
                .foregroundStyle(HoardTheme.parchment)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(HoardTheme.gold)
            Text("No recommendations yet")
                .font(HoardTheme.titleFont(23))
            Text("Visit Import and paste an Instagram Reel. The library will remember the books and why they were recommended.")
                .multilineTextAlignment(.center)
                .foregroundStyle(HoardTheme.mutedParchment)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity)
        .hoardCard()
        .padding(.top, 24)
    }
}
