import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    @State private var showIntro = IntroGate.shouldPlay
    @State private var interfaceRevealed = !IntroGate.shouldPlay

    var body: some View {
        ZStack {
            content
                .opacity(interfaceRevealed ? 1 : 0)
                .scaleEffect(interfaceRevealed ? 1 : 1.07)
                .blur(radius: interfaceRevealed ? 0 : 9)

            if showIntro {
                CastleFlightIntroView(
                    onRevealInterface: {
                        withAnimation(.easeOut(duration: 0.85)) { interfaceRevealed = true }
                    },
                    onFinished: { showIntro = false }
                )
            }
        }
    }

    private var content: some View {
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
    @State private var selectedTab = ProcessInfo.processInfo.arguments.contains("-hoard-import") ? 1 : 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                LibraryView(recommendations: appState.recommendations)
            }
            .tabItem {
                Label("Library", systemImage: "books.vertical.fill")
            }
            .tag(0)

            NavigationStack {
                ImportView(onImported: { books in
                               Task { await appState.adopt(books) }
                           },
                           customWords: appState.customWordsForOCR())
            }
            .tabItem {
                Label("Import", systemImage: "sparkles.rectangle.stack")
            }
            .tag(1)
        }
        .tint(HoardTheme.gold)
        .task { await appState.loadLibrary() }
    }
}
