import SwiftUI

/// Draws the key art, flies the camera into its doorway, and animates the few
/// things the painting implies are moving: water, fire, lamplight, stars.
enum IntroRenderer {

    // MARK: - Entry point

    static func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let cam = IntroBackdrop.camera(t: t, size: size)
        let gate = cam.point(IntroBackdrop.gate)
        let bloom = IntroBackdrop.bloom(t)

        let worldAlpha = (1 - smooth(t, IntroTimeline.worldFadeOut, IntroTimeline.flashFull))
            * smooth(t, 0, IntroTimeline.fadeIn)

        if worldAlpha > 0.004 {
            var world = ctx
            world.opacity = worldAlpha

            // Once the dragon is home, plate + sprite is the painting again, so
            // cross-fade to the untouched original and let it carry the finish.
            let settled = smooth(t, IntroTimeline.handover, IntroTimeline.handover + 0.8)
            if settled < 0.999 {
                world.draw(world.resolve(IntroBackdrop.plate.interpolation(.high)), in: cam.drawRect)
                drawFlyingDragon(&world, size: size, cam: cam, t: t)
            }
            if settled > 0.001 {
                var top = world
                top.opacity = world.opacity * settled
                top.draw(top.resolve(IntroBackdrop.original.interpolation(.high)), in: cam.drawRect)
            }

            drawTwinkle(&world, size: size, cam: cam, t: t, approach: bloom)
            drawLights(&world, size: size, cam: cam, t: t)
            drawFire(&world, size: size, cam: cam, t: t)
            drawWater(&world, size: size, cam: cam, t: t)
            drawDoors(&world, size: size, cam: cam, t: t)
            drawGateGlow(&world, size: size, cam: cam, gate: gate, bloom: bloom)
            drawVignette(&world, size: size, center: gate)
        }

        drawFlood(&ctx, size: size, center: gate, t: t, approach: bloom)
        drawStardust(&ctx, size: size, center: gate, t: t)
    }

    // MARK: - The dragon on the wing

    private static func drawFlyingDragon(
        _ ctx: inout GraphicsContext, size: CGSize, cam: IntroBackdrop.Camera, t: Double
    ) {
        let alpha = IntroBackdrop.dragonAlpha(t)
        guard alpha > 0.004 else { return }

        let s = IntroBackdrop.dragonScale(t)
        let centre = IntroBackdrop.dragonCentre(t)
        let anchor = IntroBackdrop.dragonAnchor

        // Image-space placement, then through the camera.
        let originImage = CGPoint(x: centre.x - anchor.x * s, y: centre.y - anchor.y * s)
        let rect = CGRect(
            x: cam.origin.x + originImage.x * cam.scale,
            y: cam.origin.y + originImage.y * cam.scale,
            width: IntroBackdrop.size.width * s * cam.scale,
            height: IntroBackdrop.size.height * s * cam.scale
        )
        guard rect.intersects(CGRect(origin: .zero, size: size).insetBy(dx: -400, dy: -400)) else { return }

        var g = ctx
        g.opacity = ctx.opacity * alpha
        let pivot = cam.point(centre)
        g.translateBy(x: pivot.x, y: pivot.y)
        g.rotate(by: Angle(radians: IntroBackdrop.dragonRoll(t)))
        g.translateBy(x: -pivot.x, y: -pivot.y)
        g.draw(g.resolve(IntroBackdrop.dragon.interpolation(.high)), in: rect)
    }

    // MARK: - The doors

    private static func drawDoors(
        _ ctx: inout GraphicsContext, size: CGSize, cam: IntroBackdrop.Camera, t: Double
    ) {
        let open = smooth(t, IntroTimeline.doorsOpen, IntroTimeline.doorsOpenEnd)
        guard open > 0.004 else { return }

        let half = IntroBackdrop.doorHalfWidth * open
        let a = cam.point(CGPoint(x: IntroBackdrop.doorCentre.x - half, y: IntroBackdrop.doorTop))
        let b = cam.point(CGPoint(x: IntroBackdrop.doorCentre.x + half, y: IntroBackdrop.doorBottom))
        let gap = CGRect(x: a.x, y: a.y, width: max(0.6, b.x - a.x), height: max(1, b.y - a.y))
        guard gap.intersects(CGRect(origin: .zero, size: size)) else { return }

        var g = ctx
        g.blendMode = .plusLighter
        g.fill(
            Path(gap),
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 1.0, green: 0.90, blue: 0.66).opacity(0.62 * open),
                    Color(red: 1.0, green: 0.82, blue: 0.50).opacity(0.86 * open)
                ]),
                startPoint: CGPoint(x: gap.midX, y: gap.minY),
                endPoint: CGPoint(x: gap.midX, y: gap.maxY)
            )
        )

        // Light thrown out across the threshold.
        let spill = max(4.0, gap.width * 2.6)
        g.fill(
            Path(ellipseIn: CGRect(x: gap.midX - spill, y: gap.maxY - spill * 0.55,
                                   width: spill * 2, height: spill * 1.1)),
            with: .radialGradient(
                Gradient(colors: [
                    Color(red: 1.0, green: 0.86, blue: 0.58).opacity(0.30 * open),
                    .clear
                ]),
                center: CGPoint(x: gap.midX, y: gap.maxY),
                startRadius: 0, endRadius: spill
            )
        )
    }

    @inline(__always) private static func pulse(_ t: Double, center: Double, halfWidth: Double) -> Double {
        let d = 1 - abs(t - center) / halfWidth
        guard d > 0 else { return 0 }
        return sin(d * .pi / 2)
    }

    // MARK: - Sky

    private static func drawTwinkle(
        _ ctx: inout GraphicsContext, size: CGSize, cam: IntroBackdrop.Camera,
        t: Double, approach: Double
    ) {
        let fade = smooth(t, 0.2, 1.6) * (1 - 0.55 * approach)
        guard fade > 0.01 else { return }
        let frame = CGRect(origin: .zero, size: size)
        var g = ctx
        g.blendMode = .plusLighter
        for star in IntroBackdrop.twinkles {
            let p = cam.point(star.point)
            guard frame.insetBy(dx: -6, dy: -6).contains(p) else { continue }
            let twinkle = 0.35 + 0.65 * (0.5 + 0.5 * sin(t * star.rate + star.phase))
            let r = max(0.6, cam.length(star.radius))
            g.fill(
                Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                with: .color(Color(red: 1.0, green: 0.97, blue: 0.90).opacity(0.75 * twinkle * fade))
            )
        }
    }

    // MARK: - Lamplight

    private static func drawLights(
        _ ctx: inout GraphicsContext, size: CGSize, cam: IntroBackdrop.Camera, t: Double
    ) {
        let frame = CGRect(origin: .zero, size: size).insetBy(dx: -120, dy: -120)
        var g = ctx
        g.blendMode = .plusLighter
        for (index, light) in IntroBackdrop.lights.enumerated() {
            let p = cam.point(light.point)
            guard frame.contains(p) else { continue }
            let rate = 1.1 + Double(index % 5) * 0.37
            let flicker = 0.62 + 0.38 * (0.5 + 0.5 * sin(t * rate + Double(index) * 1.9))
            let r = max(2.0, cam.length(light.radius * 1.9))
            guard r < 900 else { continue }
            g.fill(
                Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: IntroPalette.brightGold.opacity(0.30 * flicker), location: 0.0),
                        .init(color: IntroPalette.gold.opacity(0.14 * flicker), location: 0.45),
                        .init(color: .clear, location: 1.0)
                    ]),
                    center: p, startRadius: 0, endRadius: r
                )
            )
        }
    }

    // MARK: - The dragon's breath

    private static func drawFire(
        _ ctx: inout GraphicsContext, size: CGSize, cam: IntroBackdrop.Camera, t: Double
    ) {
        let mouth = cam.point(IntroBackdrop.mouth(t))
        let breathScale = IntroBackdrop.dragonScale(t)
        let frame = CGRect(origin: .zero, size: size).insetBy(dx: -400, dy: -400)
        guard frame.contains(mouth) else { return }

        var g = ctx
        g.blendMode = .plusLighter

        // The burst already painted at the muzzle, kept alive.
        let flicker = 0.66 + 0.34 * sin(t * 6.1) * sin(t * 2.7 + 1.1)
        let roar = max(pulse(t, center: 3.10, halfWidth: 0.95), pulse(t, center: 6.85, halfWidth: 0.80))
        let core = max(3.0, cam.length(26 * breathScale * (1 + 0.30 * flicker + 0.55 * roar)))
        guard core < 2400 else { return }
        g.fill(
            Path(ellipseIn: CGRect(x: mouth.x - core, y: mouth.y - core, width: core * 2, height: core * 2)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: Color(red: 1.0, green: 0.88, blue: 0.62).opacity(0.55 * (0.55 + 0.45 * flicker)), location: 0.0),
                    .init(color: Color(red: 0.96, green: 0.52, blue: 0.18).opacity(0.34), location: 0.40),
                    .init(color: Color(red: 0.62, green: 0.20, blue: 0.06).opacity(0.12), location: 0.72),
                    .init(color: .clear, location: 1.0)
                ]),
                center: mouth, startRadius: 0, endRadius: core
            )
        )

        // A longer plume when it draws breath, thrown up and to the left as painted.
        if roar > 0.02 {
            for step in 0..<7 {
                let f = Double(step) / 6
                let reach = cam.length(64 * breathScale * roar * f)
                let wobble = sin(t * 7.3 + f * 5.0) * cam.length(7 * breathScale * f)
                let p = CGPoint(x: mouth.x - reach * 0.42 + wobble, y: mouth.y - reach)
                let r = max(2.0, cam.length((17 - 9 * f) * breathScale * (0.6 + 0.7 * roar)))
                guard r < 1200 else { continue }
                g.fill(
                    Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                    with: .radialGradient(
                        Gradient(colors: [
                            Color(red: 1.0, green: 0.80, blue: 0.44).opacity(0.34 * roar * (1 - f * 0.7)),
                            Color(red: 0.90, green: 0.36, blue: 0.10).opacity(0.14 * roar * (1 - f)),
                            .clear
                        ]),
                        center: p, startRadius: 0, endRadius: r
                    )
                )
            }
        }

        // Embers riding the updraught.
        for ember in IntroBackdrop.embers {
            let age = (t * 0.42 + ember.phase).truncatingRemainder(dividingBy: 1)
            let travel = ember.speed * age
            let origin = IntroBackdrop.mouth(t)
            let p = cam.point(CGPoint(
                x: origin.x + (cos(ember.angle) * travel + sin(t * 2 + ember.phase * 9) * 5) * breathScale,
                y: origin.y - sin(ember.angle) * travel * 1.3 * breathScale
            ))
            let r = max(0.5, cam.length(ember.size * breathScale))
            guard r < 40 else { continue }
            let alpha = (1 - age) * (1 - age) * (0.45 + 0.55 * roar)
            g.fill(
                Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                with: .color(Color(red: 1.0, green: 0.66, blue: 0.28).opacity(0.7 * alpha))
            )
        }
    }

    // MARK: - Water

    private static func drawWater(
        _ ctx: inout GraphicsContext, size: CGSize, cam: IntroBackdrop.Camera, t: Double
    ) {
        let frame = CGRect(origin: .zero, size: size)
        var g = ctx
        g.blendMode = .plusLighter
        let swell = sin(t * 0.45) * 2.4

        for (index, glint) in IntroBackdrop.glints.enumerated() {
            let wobble = sin(t * glint.rate + glint.phase) * glint.drift
            let breathe = 0.42 + 0.58 * (0.5 + 0.5 * sin(t * (glint.rate * 1.7) + glint.phase * 2.1))
            let centre = CGPoint(x: glint.point.x + wobble, y: glint.point.y + swell)
            let a = cam.point(CGPoint(x: centre.x - glint.length / 2, y: centre.y))
            let b = cam.point(CGPoint(x: centre.x + glint.length / 2, y: centre.y))
            guard max(a.x, b.x) > -40, min(a.x, b.x) < size.width + 40,
                  a.y > frame.minY - 40, a.y < frame.maxY + 40 else { continue }

            var line = Path()
            line.move(to: a)
            line.addLine(to: b)
            let width = max(0.7, cam.length(2.2 + Double(index % 3)))
            g.stroke(
                line,
                with: .color((glint.warm ? IntroPalette.gold : Color(red: 0.66, green: 0.72, blue: 0.86))
                    .opacity(0.16 * breathe)),
                style: StrokeStyle(lineWidth: width, lineCap: .round)
            )
        }
    }

    // MARK: - The doorway

    private static func drawGateGlow(
        _ ctx: inout GraphicsContext, size: CGSize, cam: IntroBackdrop.Camera,
        gate: CGPoint, bloom: Double
    ) {
        var g = ctx
        g.blendMode = .plusLighter
        let swell = pow(bloom, 1.6)
        let r = max(6.0, cam.length(IntroBackdrop.gateGlowRadius) * (1 + 5.0 * swell))
        g.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: Color(red: 1.0, green: 0.93, blue: 0.74).opacity(0.16 + 0.66 * swell), location: 0.0),
                    .init(color: IntroPalette.gold.opacity(0.10 + 0.34 * swell), location: 0.36),
                    .init(color: IntroPalette.ember.opacity(0.06 + 0.10 * swell), location: 0.66),
                    .init(color: .clear, location: 1.0)
                ]),
                center: gate, startRadius: 0, endRadius: r
            )
        )
    }

    private static func drawVignette(_ ctx: inout GraphicsContext, size: CGSize, center: CGPoint) {
        ctx.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: .clear, location: 0.42),
                    .init(color: Color.black.opacity(0.22), location: 0.80),
                    .init(color: Color.black.opacity(0.52), location: 1.0)
                ]),
                center: CGPoint(x: size.width / 2, y: size.height * 0.5),
                startRadius: 0,
                endRadius: max(size.width, size.height) * 0.82
            )
        )
    }

    // MARK: - Passing into the light

    private static func drawFlood(
        _ ctx: inout GraphicsContext, size: CGSize, center: CGPoint, t: Double, approach: Double
    ) {
        let floodAlpha = clamp01(
            smooth(t, IntroTimeline.floodStart, IntroTimeline.flashFull)
                - smooth(t, IntroTimeline.flashFull + 0.40, IntroTimeline.floodOutEnd)
        )
        guard floodAlpha > 0.004 else { return }

        var g = ctx
        g.opacity = floodAlpha
        g.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: Color(red: 1.0, green: 0.975, blue: 0.90), location: 0.0),
                    .init(color: IntroPalette.brightGold, location: 0.38),
                    .init(color: IntroPalette.gold, location: 0.70),
                    .init(color: Color(red: 0.52, green: 0.27, blue: 0.14), location: 1.0)
                ]),
                center: center,
                startRadius: 0,
                endRadius: max(size.width, size.height) * 0.95
            )
        )

        let whiteFlash = pulse(t, center: IntroTimeline.flashFull + 0.12, halfWidth: 0.42)
        if whiteFlash > 0.01 {
            var flash = ctx
            flash.blendMode = .plusLighter
            flash.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(Color.white.opacity(0.42 * whiteFlash))
            )
        }
    }

    // MARK: - Stardust

    private static func drawStardust(
        _ ctx: inout GraphicsContext, size: CGSize, center gate: CGPoint, t: Double
    ) {
        let elapsed = t - IntroTimeline.dustStart
        guard elapsed > 0, t < IntroTimeline.dustEnd + 0.3 else { return }

        let center = CGPoint(
            x: min(max(gate.x, size.width * 0.3), size.width * 0.7),
            y: min(max(gate.y, size.height * 0.3), size.height * 0.6)
        )
        let maxRadius = max(size.width, size.height) * 0.82

        var g = ctx
        g.blendMode = .plusLighter

        for (delay, span, weight) in [(0.0, 1.5, 1.0), (0.18, 2.1, 0.55)] {
            let progress = smooth(t, IntroTimeline.dustStart + delay, IntroTimeline.dustStart + delay + span)
            guard progress > 0.01, progress < 0.999 else { continue }
            let r = 26 + maxRadius * 1.2 * progress
            g.stroke(
                Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                with: .color(IntroPalette.brightGold.opacity(0.15 * weight * (1 - progress))),
                lineWidth: 1 + 4.5 * (1 - progress)
            )
        }

        for mote in IntroScatter.motes {
            let age = elapsed - mote.delay
            guard age > 0 else { continue }
            let life = mote.life * 1.7
            guard age < life else { continue }
            let u = age / life

            let radius = mote.speed * (1 - exp(-age * 1.7)) * maxRadius
            let theta = mote.angle + mote.swirl * 0.62 * (1 - exp(-age * 1.15))
            let x = center.x + cos(theta) * radius
            let y = center.y + sin(theta) * radius * 0.94 + mote.drift * age * age * 20

            guard x > -40, x < size.width + 40, y > -40, y < size.height + 40 else { continue }

            let alpha = smooth(age, 0, 0.16) * (1 - smooth(u, 0.5, 1.0))
            guard alpha > 0.01 else { continue }

            let color = mote.warmth > 0.74
                ? IntroPalette.parchment
                : (mote.warmth > 0.09 ? IntroPalette.brightGold : IntroPalette.ember)
            let r = mote.size * (0.55 + 0.65 * (1 - u))

            g.fill(
                IntroShapes.sparkle(center: CGPoint(x: x, y: y), radius: r, rotation: mote.spin * age),
                with: .color(color.opacity(0.72 * alpha))
            )
            g.fill(
                Path(ellipseIn: CGRect(x: x - r * 0.16, y: y - r * 0.16, width: r * 0.32, height: r * 0.32)),
                with: .color(Color.white.opacity(0.7 * alpha))
            )
        }
    }
}
