import SwiftUI
import UIKit

/// Decides whether the first-launch flight plays.
enum IntroGate {
    static let seenKey = "hasSeenCastleFlightIntro"

    static var shouldPlay: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-hoard-skip-intro") { return false }
        if arguments.contains("-hoard-force-intro") { return true }
        if UIAccessibility.isReduceMotionEnabled { return false }
        return !UserDefaults.standard.bool(forKey: seenKey)
    }

    static func markSeen() {
        UserDefaults.standard.set(true, forKey: seenKey)
    }

    /// Launch with `-hoardIntroFreeze <seconds>` to hold the flight on one frame
    /// while tuning it.
    static var frozenTime: Double? {
        guard UserDefaults.standard.object(forKey: "hoardIntroFreeze") != nil else { return nil }
        return UserDefaults.standard.double(forKey: "hoardIntroFreeze")
    }

    /// Launch with `-hoardIntroSpeed 0.5` to run the flight at half rate. Used to
    /// capture a smooth recording on a simulator that cannot sustain 60fps, then
    /// retimed back to normal speed in the export.
    static var speed: Double {
        guard UserDefaults.standard.object(forKey: "hoardIntroSpeed") != nil else { return 1 }
        let value = UserDefaults.standard.double(forKey: "hoardIntroSpeed")
        return value > 0.05 ? value : 1
    }
}

/// The very first thing a new keeper sees: a dragon running the river to the
/// castle, a flight through its open doors, and the library waiting inside.
struct CastleFlightIntroView: View {
    /// Fired when the gold light should hand over to the real interface.
    var onRevealInterface: () -> Void
    /// Fired once the last of the stardust has settled.
    var onFinished: () -> Void

    @State private var startedAt = Date()
    @State private var isInteractive = true
    @State private var backdropOpacity = 1.0

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = IntroGate.frozenTime ?? timeline.date.timeIntervalSince(startedAt) * IntroGate.speed
            Canvas(opaque: false, rendersAsynchronously: false) { context, size in
                IntroRenderer.draw(&context, size: size, t: t)
            }
        }
        .ignoresSafeArea()
        .background(IntroPalette.night.opacity(backdropOpacity).ignoresSafeArea())
        .allowsHitTesting(isInteractive)
        .accessibilityHidden(true)
        .statusBarHidden(isInteractive)
        .onAppear(perform: start)
    }

    private func start() {
        startedAt = Date()
        IntroGate.markSeen()
        guard IntroGate.frozenTime == nil else { return }

        let rate = IntroGate.speed
        DispatchQueue.main.asyncAfter(deadline: .now() + IntroTimeline.revealUI / rate) {
            isInteractive = false
            withAnimation(.easeOut(duration: 0.6)) { backdropOpacity = 0 }
            onRevealInterface()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + IntroTimeline.total / rate) {
            onFinished()
        }
    }
}

#Preview {
    CastleFlightIntroView(onRevealInterface: {}, onFinished: {})
}
