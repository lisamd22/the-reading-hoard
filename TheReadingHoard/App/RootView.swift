import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingView { profile in
                    appState.completeOnboarding(with: profile)
                }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: appState.hasCompletedOnboarding)
    }
}

private struct MainTabView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            NavigationStack {
                LibraryView(recommendations: appState.recommendations)
            }
            .tabItem {
                Label("Library", systemImage: "books.vertical.fill")
            }

            NavigationStack {
                ImportView(importer: MockRecommendationImporter()) { recommendation in
                    appState.add(recommendation)
                }
            }
            .tabItem {
                Label("Import", systemImage: "sparkles.rectangle.stack")
            }
        }
        .tint(HoardTheme.gold)
    }
}
