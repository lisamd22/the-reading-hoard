import SwiftUI

enum HoardTheme {
    static let ink = Color(red: 0.055, green: 0.047, blue: 0.075)
    static let midnight = Color(red: 0.095, green: 0.075, blue: 0.12)
    static let plum = Color(red: 0.21, green: 0.105, blue: 0.15)
    static let parchment = Color(red: 0.94, green: 0.88, blue: 0.74)
    static let mutedParchment = Color(red: 0.72, green: 0.66, blue: 0.57)
    static let gold = Color(red: 0.79, green: 0.61, blue: 0.27)
    static let ember = Color(red: 0.67, green: 0.25, blue: 0.15)
    static let moss = Color(red: 0.20, green: 0.34, blue: 0.25)

    static let background = LinearGradient(
        colors: [ink, midnight, plum.opacity(0.75)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func titleFont(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }
}

struct HoardCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(HoardTheme.midnight.opacity(0.86), in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(HoardTheme.gold.opacity(0.24), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.25), radius: 18, y: 10)
    }
}

extension View {
    func hoardCard() -> some View {
        modifier(HoardCardModifier())
    }
}
