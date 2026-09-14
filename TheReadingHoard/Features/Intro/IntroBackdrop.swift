import SwiftUI

/// The painted key art, split into a plate with the dragon removed and the
/// dragon itself, so the dragon can fly in and land back into its own pose.
///
/// Every coordinate is in image pixels (941 x 1672), measured off the artwork.
enum IntroBackdrop {

    static let size = CGSize(width: 941, height: 1672)

    /// Replaced by the macOS preview harness, which has no asset catalog.
    static var plate = Image("IntroPlate")
    static var dragon = Image("IntroDragon")
    static var original = Image("IntroBackdrop")

    // MARK: - Features, measured off the artwork

    static let gate = CGPoint(x: 462, y: 930)
    static let gateGlowRadius: Double = 44
    /// The wooden doors below the traceried window.
    static let doorCentre = CGPoint(x: 462, y: 972)
    static let doorHalfWidth: Double = 18
    static let doorTop: Double = 944
    static let doorBottom: Double = 998
    static let waterLine: Double = 1098
    /// Where the dragon rests, and where its muzzle sits when it does.
    static let dragonAnchor = CGPoint(x: 716, y: 806)
    static let dragonMouth = CGPoint(x: 620, y: 620)

    static let lights: [(point: CGPoint, radius: Double)] = [
        (CGPoint(x: 361, y: 690), 15), (CGPoint(x: 375, y: 698), 9),
        (CGPoint(x: 374, y: 682), 8),  (CGPoint(x: 488, y: 950), 11),
        (CGPoint(x: 63, y: 981), 11),  (CGPoint(x: 435, y: 956), 9),
        (CGPoint(x: 236, y: 932), 9),  (CGPoint(x: 509, y: 964), 8),
        (CGPoint(x: 521, y: 691), 9),  (CGPoint(x: 517, y: 963), 8),
        (CGPoint(x: 310, y: 726), 8),  (CGPoint(x: 421, y: 964), 8),
        (CGPoint(x: 527, y: 958), 7),  (CGPoint(x: 225, y: 937), 8),
        (CGPoint(x: 327, y: 969), 7),  (CGPoint(x: 413, y: 963), 7),
        (CGPoint(x: 276, y: 789), 6),  (CGPoint(x: 311, y: 753), 6),
        (CGPoint(x: 332, y: 863), 6),  (CGPoint(x: 336, y: 635), 6),
        (CGPoint(x: 284, y: 789), 6),  (CGPoint(x: 516, y: 693), 7),
        (CGPoint(x: 450, y: 777), 7)
    ]

    // MARK: - The dragon's approach

    /// How far through its glide the dragon is: fast out of the foreground,
    /// slowing as it reaches for the perch.
    static func approach(_ t: Double) -> Double {
        let u = ramp(t, IntroTimeline.dragonEnter, IntroTimeline.dragonLand)
        return 1 - pow(1 - u, 2.1)
    }

    /// Where the dragon's body sits, in image pixels. It comes in low and near
    /// the lens, out over the water, and recedes toward the castle.
    static func dragonCentre(_ t: Double) -> CGPoint {
        let p = approach(t)
        let glide = sin(p * .pi) * 46          // a shallow arc rather than a straight line
        let bob = sin(t * 1.15) * 10 * (1 - p)
        return CGPoint(
            x: mix(238, dragonAnchor.x, pow(p, 0.88)),
            y: mix(1244, dragonAnchor.y, pow(p, 1.14)) - glide + bob
        )
    }

    static func dragonScale(_ t: Double) -> Double {
        mix(1.95, 1.0, pow(approach(t), 0.80))
    }

    /// Banks into the turn, levels off to land.
    static func dragonRoll(_ t: Double) -> Double {
        let p = approach(t)
        return (1 - p) * -0.16 + sin(t * 0.9) * 0.02 * (1 - p)
    }

    static func dragonAlpha(_ t: Double) -> Double {
        smooth(t, IntroTimeline.dragonEnter, IntroTimeline.dragonEnter + 0.55)
    }

    /// The muzzle, wherever the dragon currently is.
    static func mouth(_ t: Double) -> CGPoint {
        let s = dragonScale(t)
        let c = dragonCentre(t)
        return CGPoint(
            x: c.x + (dragonMouth.x - dragonAnchor.x) * s,
            y: c.y + (dragonMouth.y - dragonAnchor.y) * s
        )
    }

    // MARK: - Camera

    struct Camera {
        let scale: Double
        let origin: CGPoint

        func point(_ p: CGPoint) -> CGPoint {
            CGPoint(x: origin.x + p.x * scale, y: origin.y + p.y * scale)
        }
        func length(_ pixels: Double) -> Double { pixels * scale }
        var drawRect: CGRect {
            CGRect(origin: origin,
                   size: CGSize(width: IntroBackdrop.size.width * scale,
                                height: IntroBackdrop.size.height * scale))
        }
    }

    /// Enough zoom during the glide to give the camera room to track, then the
    /// long push into the doorway. Capped by the 941px source, not by taste.
    static func zoom(_ t: Double) -> Double {
        let follow = 0.34 * smooth(t, IntroTimeline.dragonEnter + 0.3, IntroTimeline.dragonLand)
        let push = 0.78 * pow(ramp(t, IntroTimeline.dragonLand - 1.4, IntroTimeline.pushEnd), 1.20)
        let surge = 0.44 * pow(smooth(t, IntroTimeline.pushEnd - 1.3, IntroTimeline.pushEnd + 0.5), 1.8)
        return 1 + follow + push + surge
    }

    static func bloom(_ t: Double) -> Double {
        smooth(t, IntroTimeline.doorsOpen, IntroTimeline.floodStart + 0.4)
    }

    static func camera(t: Double, size: CGSize) -> Camera {
        let fill = max(size.width / IntroBackdrop.size.width,
                       size.height / IntroBackdrop.size.height)
        let scale = fill * zoom(t)
        let drawn = CGSize(width: IntroBackdrop.size.width * scale,
                           height: IntroBackdrop.size.height * scale)

        // Open square on the title, then track the dragon, then hand the frame
        // to the doorway.
        let takeUp = smooth(t, IntroTimeline.dragonEnter, IntroTimeline.dragonEnter + 1.0)
        let handToGate = smooth(t, IntroTimeline.dragonLand - 2.6, IntroTimeline.dragonLand + 0.6)
        let opening = CGPoint(x: 481.5, y: 862)
        let tracked = dragonCentre(t)
        var focus = CGPoint(x: mix(opening.x, tracked.x, takeUp), y: mix(opening.y, tracked.y, takeUp))
        focus = CGPoint(x: mix(focus.x, gate.x, handToGate), y: mix(focus.y, gate.y, handToGate))
        let target = CGPoint(
            x: size.width / 2,
            y: mix(mix(0.500, 0.560, takeUp), 0.430, handToGate) * size.height
        )

        let x = min(0, max(size.width - drawn.width, target.x - focus.x * scale))
        let y = min(0, max(size.height - drawn.height, target.y - focus.y * scale))
        return Camera(scale: scale, origin: CGPoint(x: x, y: y))
    }

    // MARK: - Scatter

    struct Twinkle { let point: CGPoint; let radius: Double; let phase: Double; let rate: Double }
    struct Glint {
        let point: CGPoint; let length: Double; let phase: Double
        let rate: Double; let drift: Double; let warm: Bool
    }
    struct Ember { let angle: Double; let speed: Double; let size: Double; let phase: Double }

    static let twinkles: [Twinkle] = {
        var rng = IntroRandom(seed: 0x5A11_5A11)
        return (0..<54).map { _ in
            Twinkle(point: CGPoint(x: rng.between(30, 911), y: rng.between(40, 560)),
                    radius: rng.between(0.8, 2.4),
                    phase: rng.between(0, 6.283),
                    rate: rng.between(0.8, 2.6))
        }
    }()

    static let glints: [Glint] = {
        var rng = IntroRandom(seed: 0xD0D0_CAFE)
        return (0..<150).map { _ in
            let nearColumn = rng.unit() < 0.42
            return Glint(
                point: CGPoint(x: nearColumn ? gate.x + rng.between(-56, 56) : rng.between(10, 931),
                               y: rng.between(waterLine + 6, 1668)),
                length: rng.between(6, 46),
                phase: rng.between(0, 6.283),
                rate: rng.between(0.5, 1.9),
                drift: rng.between(3, 16),
                warm: nearColumn || rng.unit() < 0.3
            )
        }
    }()

    static let embers: [Ember] = {
        var rng = IntroRandom(seed: 0xF14E_F14E)
        return (0..<22).map { _ in
            Ember(angle: rng.between(1.9, 2.7),
                  speed: rng.between(26, 90),
                  size: rng.between(0.9, 2.8),
                  phase: rng.between(0, 1))
        }
    }()
}
