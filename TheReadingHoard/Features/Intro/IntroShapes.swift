import SwiftUI

// MARK: - Reusable glyphs

enum IntroShapes {

    /// The four-point star used across the brand marks.
    static func sparkle(center: CGPoint, radius r: Double, waist: Double = 0.30, rotation: Double = 0) -> Path {
        var path = Path()
        let w = r * waist
        path.move(to: CGPoint(x: 0, y: -r))
        path.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: w, y: -w))
        path.addQuadCurve(to: CGPoint(x: 0, y: r), control: CGPoint(x: w, y: w))
        path.addQuadCurve(to: CGPoint(x: -r, y: 0), control: CGPoint(x: -w, y: w))
        path.addQuadCurve(to: CGPoint(x: 0, y: -r), control: CGPoint(x: -w, y: -w))
        path.closeSubpath()
        var transform = CGAffineTransform(translationX: center.x, y: center.y)
        transform = transform.rotated(by: rotation)
        return path.applying(transform)
    }
}
