import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var hasCompletedOnboarding: Bool
    @Published private(set) var profile: OnboardingProfile
    @Published private(set) var recommendations: [BookRecommendation]

    private let defaults: UserDefaults
    private static let onboardingKey = "hasCompletedOnboarding"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasCompletedOnboarding = defaults.bool(forKey: Self.onboardingKey)
        profile = .empty
        recommendations = []
    }

    func completeOnboarding(with profile: OnboardingProfile) {
        self.profile = profile
        hasCompletedOnboarding = true
        defaults.set(true, forKey: Self.onboardingKey)
    }

    func add(_ recommendation: BookRecommendation) {
        recommendations = RecommendationLibrary.merging(
            current: recommendations,
            new: [recommendation]
        )
    }
}
