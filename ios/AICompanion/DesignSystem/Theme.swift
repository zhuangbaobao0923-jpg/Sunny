import SwiftUI
import UIKit

// MARK: - 设计令牌
//
// 方向：夜谈风（Immersive Dark）—— 沉浸式全屏立绘 + 暗金点缀
// 展示字：宋体系（角色名） 正文：系统 PingFang
// 金色 = 创作流程；粉色 = 亲密度专属；靛蓝 = 用户气泡

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

enum Palette {
    static let bg = Color(hex: 0x0A0A12)
    static let bg2 = Color(hex: 0x12121C)
    static let card = Color(hex: 0x191926)
    static let card2 = Color(hex: 0x20202F)

    static let line = Color.white.opacity(0.08)
    static let line2 = Color.white.opacity(0.14)

    static let ink = Color(hex: 0xF4F4F8)
    static let ink2 = Color(hex: 0xA6A6BA)
    static let ink3 = Color(hex: 0x6E6E82)

    static let gold = Color(hex: 0xE8C468)
    static let goldDeep = Color(hex: 0xB8933D)
    static let pink = Color(hex: 0xFF8FB8)
    static let pinkDeep = Color(hex: 0xE86A9C)
    static let indigo = Color(hex: 0x5B5FC7).opacity(0.92)

    static let danger = Color(hex: 0xFF5D5D)
    static let ok = Color(hex: 0x5BC98F)

    static let goldGradient = LinearGradient(
        colors: [Color(hex: 0xF2D98B), Color(hex: 0xD9AE52)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let pinkGradient = LinearGradient(
        colors: [Color(hex: 0xFFA9C9), Color(hex: 0xF0709F)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let fabGradient = LinearGradient(
        colors: [Color(hex: 0xFBFBFF), Color(hex: 0xD8D8E4)],
        startPoint: .top, endPoint: .bottom
    )

    /// 页面底色：两枚大半径径向光晕叠在近黑之上
    static var canvas: some View {
        ZStack {
            bg
            RadialGradient(
                colors: [Color(hex: 0x1D1A2E), .clear],
                center: UnitPoint(x: 0.15, y: -0.1),
                startRadius: 0, endRadius: 620
            )
            RadialGradient(
                colors: [Color(hex: 0x14202B), .clear],
                center: UnitPoint(x: 1.1, y: 1.1),
                startRadius: 0, endRadius: 520
            )
        }
        .ignoresSafeArea()
    }
}

enum Radius {
    static let sm: CGFloat = 12
    static let md: CGFloat = 14
    static let lg: CGFloat = 16
    static let xl: CGFloat = 22
    static let capsule: CGFloat = 26
}

enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 22
    /// 触控目标下限（iOS HIG 44pt）
    static let hit: CGFloat = 44
}

enum Motion {
    static let smooth = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.38)
    static let quick = Animation.easeOut(duration: 0.16)
}

enum Typo {
    /// 角色名/标题的宋体展示字，缺字族时退到系统衬线
    static func display(_ size: CGFloat, bold: Bool = true) -> Font {
        let postScript = bold ? "STSongti-SC-Bold" : "STSongti-SC-Regular"
        if UIFont(name: postScript, size: size) != nil {
            return .custom(postScript, size: size)
        }
        return .system(size: size, weight: bold ? .semibold : .regular, design: .serif)
    }

    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}
