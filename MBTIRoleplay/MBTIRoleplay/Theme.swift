import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: 1.0
        )
    }
}

enum Theme {
    static let bg = Color(hex: 0xF6F7FB)
    static let card = Color.white
    static let ink = Color(hex: 0x1F2329)
    static let ink2 = Color(hex: 0x5A6070)
    static let ink3 = Color(hex: 0x9AA0AE)
    static let line = Color(hex: 0xE7EAF0)
    static let accent = Color(hex: 0x5B5BD6)
    static let accentSoft = Color(hex: 0xEEEEFC)
    static let warm = Color(hex: 0xD4649A)
    static let green = Color(hex: 0x2E9E6B)
    static let amber = Color(hex: 0xC98A1B)

    static let heroGradient = LinearGradient(
        colors: [Color(hex: 0x5B5BD6), Color(hex: 0x8A63D2), Color(hex: 0xD4649A)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let avatarPalettes: [(Color, Color)] = [
        (Color(hex: 0x7F77DD), Color(hex: 0xB9A6F2)),
        (Color(hex: 0xD4537E), Color(hex: 0xF2A6C0)),
        (Color(hex: 0x1D9E75), Color(hex: 0x8ED9BC)),
        (Color(hex: 0xBA7517), Color(hex: 0xF0C67E)),
        (Color(hex: 0x378ADD), Color(hex: 0x9CC6F2)),
        (Color(hex: 0x993556), Color(hex: 0xE09BB3))
    ]

    static func avatarGradient(_ index: Int) -> LinearGradient {
        let pair = avatarPalettes[abs(index) % avatarPalettes.count]
        return LinearGradient(colors: [pair.0, pair.1], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.line, lineWidth: 0.8)
            )
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View {
        modifier(CardModifier(padding: padding))
    }
}
