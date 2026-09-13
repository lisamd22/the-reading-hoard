import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var hasCompletedOnboarding: Bool
    @Published private(set) var profile: OnboardingProfile
    @Published private(set) var recommendations: [BookRecommendation]
    /// Near-duplicates the merge could not decide on. Surfaced for user review
    /// rather than silently merged or silently duplicated.
    @Published private(set) var pendingMerges: [(existing: BookRecommendation, incoming: BookRecommendation)] = []

    private let defaults: UserDefaults
    private let store: LibraryStore?
    private static let onboardingKey = "hasCompletedOnboarding"

    init(defaults: UserDefaults = .standard, store: LibraryStore? = nil) {
        self.defaults = defaults
        profile = .empty

        if ProcessInfo.processInfo.arguments.contains("-hoard-demo") {
            hasCompletedOnboarding = true
            recommendations = BookRecommendation.demoShelf
            self.store = nil            // demo runs are ephemeral by design
        } else {
            hasCompletedOnboarding = defaults.bool(forKey: Self.onboardingKey)
            recommendations = []
            self.store = store ?? LibraryStore(fileURL: LibraryStore.defaultURL())
        }
    }

    /// Load the persisted library. Call once on appear.
    func loadLibrary() async {
        guard let store else { return }
        recommendations = await store.books()
    }

    func completeOnboarding(with profile: OnboardingProfile) {
        self.profile = profile
        hasCompletedOnboarding = true
        defaults.set(true, forKey: Self.onboardingKey)
    }

    /// The single write path into the library.
    func adopt(_ incoming: [BookRecommendation]) async {
        guard let store else {
            recommendations = RecommendationLibrary
                .merging(current: recommendations, incoming: incoming).library
            return
        }
        do {
            let result = try await store.add(incoming)
            recommendations = result.library
            pendingMerges.append(contentsOf: result.needsUserDecision)
        } catch {
            // Keep the books in memory even if the write failed; the next
            // successful write persists them.
            recommendations = RecommendationLibrary
                .merging(current: recommendations, incoming: incoming).library
        }
    }

    func adopt(_ recommendation: BookRecommendation) async {
        await adopt([recommendation])
    }

    func update(_ book: BookRecommendation) async {
        guard let store else {
            if let i = recommendations.firstIndex(where: { $0.id == book.id }) {
                recommendations[i] = book
            }
            return
        }
        if let updated = try? await store.update(book) { recommendations = updated }
    }

    func resolvePendingMerge(at index: Int, treatAsSame: Bool) async {
        guard pendingMerges.indices.contains(index) else { return }
        let pair = pendingMerges.remove(at: index)
        if treatAsSame {
            await update(pair.existing.absorbing(pair.incoming))
        } else {
            guard let store else { recommendations.append(pair.incoming); return }
            if let result = try? await store.add([pair.incoming]) { recommendations = result.library }
        }
    }

    /// Author names already in the library, fed to Vision as `customWords` so OCR
    /// stops mangling names it has seen before.
    func customWordsForOCR() -> [String] {
        var words = Set<String>()
        for book in recommendations {
            if let author = book.author {
                for part in author.split(separator: " ") where part.count > 2 {
                    words.insert(String(part))
                }
            }
        }
        return Array(words)
    }
}

// Sample shelf used when the app is launched with `-hoard-demo`, so screen
// recordings and previews land on a populated library.
extension BookRecommendation {
    static let demoShelf: [BookRecommendation] = [
        BookRecommendation(
            title: "The Gilded Thorn",
            author: "Marisol Vane",
            recommendationSummary: "Saved from a Reel about slow-burn court intrigue and a heroine who bargains with her own kingdom."
        ),
        BookRecommendation(
            title: "Salt and Sovereign",
            author: "E. R. Halloway",
            recommendationSummary: "Recommended for the shipwrecked cartography, the found family, and one very stubborn lighthouse keeper.",
            status: .reading
        ),
        BookRecommendation(
            title: "A Chorus of Quiet Wolves",
            author: "Nadia Brennan",
            recommendationSummary: "Tagged as the gentlest fantasy of the year. Slow mornings, old libraries, and a curse that fades by candlelight."
        )
    ]
}
