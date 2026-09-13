import SwiftUI

// MARK: - Timeline

enum IntroTimeline {
    static let fadeIn        = 1.00
    static let dragonEnter   = 2.00
    static let dragonLand    = 6.90
    static let handover      = 7.10   // plate + sprite gives way to the original art
    static let doorsOpen     = 6.10
    static let doorsOpenEnd  = 8.20
    static let pushEnd       = 10.40
    static let floodStart    = 9.70
    static let worldFadeOut  = 10.00
    static let flashFull     = 10.50
    static let dustStart     = 10.70
    static let revealUI      = 11.00
    static let floodOutEnd   = 11.95
    static let dustEnd       = 13.20
    static let total         = 13.40
}

// MARK: - Palette

enum IntroPalette {
    static let ink        = Color(red: 0.055, green: 0.047, blue: 0.075)
    static let midnight   = Color(red: 0.095, green: 0.075, blue: 0.120)
    static let plum       = Color(red: 0.210, green: 0.105, blue: 0.150)
    static let parchment  = Color(red: 0.940, green: 0.880, blue: 0.740)
    static let gold       = Color(red: 0.790, green: 0.610, blue: 0.270)
    static let brightGold = Color(red: 0.985, green: 0.855, blue: 0.545)
    static let ember      = Color(red: 0.670, green: 0.250, blue: 0.150)
    static let stone      = Color(red: 0.072, green: 0.068, blue: 0.086)
    static let stoneWarm  = Color(red: 0.140, green: 0.108, blue: 0.104)
    static let water      = Color(red: 0.055, green: 0.068, blue: 0.115)
    static let night      = Color(red: 0.030, green: 0.026, blue: 0.046)
}

// MARK: - Math helpers

@inline(__always) func clamp01(_ v: Double) -> Double { min(max(v, 0), 1) }

@inline(__always) func ramp(_ t: Double, _ a: Double, _ b: Double) -> Double {
    guard b > a else { return t >= b ? 1 : 0 }
    return clamp01((t - a) / (b - a))
}

@inline(__always) func smooth(_ t: Double, _ a: Double, _ b: Double) -> Double {
    let u = ramp(t, a, b)
    return u * u * (3 - 2 * u)
}

@inline(__always) func mix(_ a: Double, _ b: Double, _ u: Double) -> Double { a + (b - a) * u }

// MARK: - Deterministic randomness

struct IntroRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 2862933555777941757 &+ 3037000493 }

    mutating func unit() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let bits = (state >> 11) & 0x1F_FFFF_FFFF_FFFF
        return Double(bits) / Double(1 << 53)
    }

    mutating func between(_ a: Double, _ b: Double) -> Double { a + (b - a) * unit() }
}

// MARK: - Stardust scatter

struct IntroMote {
    let angle: Double
    let speed: Double
    let size: Double
    let spin: Double
    let delay: Double
    let life: Double
    let warmth: Double
    let drift: Double
    let swirl: Double
}

enum IntroScatter {
    static let motes: [IntroMote] = {
        var rng = IntroRandom(seed: 0xD057_5741)
        return (0..<96).map { i in
            IntroMote(
                angle: rng.between(0, 6.283),
                speed: pow(rng.between(0.06, 1.0), 0.72),
                size: rng.between(1.6, 7.0),
                spin: rng.between(-2.6, 2.6),
                delay: pow(rng.between(0, 1), 1.9) * 0.85,
                life: rng.between(1.5, 2.6),
                warmth: rng.between(0, 1),
                drift: rng.between(-0.2, 1.0),
                swirl: i % 2 == 0 ? 1 : -1
            )
        }
    }()
}
