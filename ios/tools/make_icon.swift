// 生成「夜谈」App 图标 1024x1024（不透明，无 alpha，符合 App Store 要求）
// 用法：swift make_icon.swift <输出路径>
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let S: CGFloat = 1024
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"

let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil, width: Int(S), height: Int(S),
    bitsPerComponent: 8, bytesPerRow: 0, space: cs,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { exit(1) }

// 1. 夜空底色：深靛 → 深紫 → 近黑
let bgColors = [
    CGColor(red: 0.055, green: 0.070, blue: 0.145, alpha: 1),
    CGColor(red: 0.105, green: 0.075, blue: 0.200, alpha: 1),
    CGColor(red: 0.035, green: 0.030, blue: 0.075, alpha: 1),
] as CFArray
let bg = CGGradient(colorsSpace: cs, colors: bgColors, locations: [0, 0.52, 1])!
ctx.drawLinearGradient(
    bg,
    start: CGPoint(x: 120, y: S),
    end: CGPoint(x: S * 0.85, y: 0),
    options: []
)

// 2. 月亮背后的暖光晕
let moonC = CGPoint(x: 490, y: 575)
let glowColors = [
    CGColor(red: 0.98, green: 0.90, blue: 0.74, alpha: 0.30),
    CGColor(red: 0.85, green: 0.72, blue: 0.95, alpha: 0.10),
    CGColor(red: 0.85, green: 0.72, blue: 0.95, alpha: 0.0),
] as CFArray
let glow = CGGradient(colorsSpace: cs, colors: glowColors, locations: [0, 0.45, 1])!
ctx.drawRadialGradient(
    glow,
    startCenter: moonC, startRadius: 0,
    endCenter: moonC, endRadius: 470,
    options: [.drawsBeforeStartLocation]
)

// 3. 星点（固定分布，避免随机不可复现）
let stars: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
    (196, 792, 9, 0.85), (300, 700, 5, 0.55), (148, 640, 4, 0.45),
    (352, 862, 6, 0.65), (770, 812, 7, 0.60), (860, 700, 4.5, 0.45),
    (676, 900, 4, 0.50), (880, 560, 5, 0.40), (250, 500, 3.5, 0.35),
    (420, 900, 3, 0.40), (806, 400, 3.5, 0.30), (120, 880, 3, 0.35),
]
for (x, y, r, a) in stars {
    let c = CGPoint(x: x, y: y)
    // 微弱外晕
    let sc = [
        CGColor(red: 1, green: 0.97, blue: 0.90, alpha: a * 0.35),
        CGColor(red: 1, green: 0.97, blue: 0.90, alpha: 0),
    ] as CFArray
    if let sg = CGGradient(colorsSpace: cs, colors: sc, locations: [0, 1]) {
        ctx.drawRadialGradient(sg, startCenter: c, startRadius: 0,
                               endCenter: c, endRadius: r * 3.2, options: [])
    }
    ctx.setFillColor(CGColor(red: 1, green: 0.98, blue: 0.93, alpha: a))
    ctx.fillEllipse(in: CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r))
}

// 4. 主体：一弯月牙（内圆完全含于外圆，even-odd 挖空）
let moon = CGMutablePath()
moon.addEllipse(in: CGRect(x: moonC.x - 262, y: moonC.y - 262, width: 524, height: 524))
moon.addEllipse(in: CGRect(x: moonC.x - 262 + 109, y: moonC.y - 262 + 102, width: 396, height: 396))

ctx.saveGState()
// 月牙本体的柔光扩散
ctx.setShadow(
    offset: .zero, blur: 90,
    color: CGColor(red: 0.98, green: 0.90, blue: 0.72, alpha: 0.55)
)
ctx.addPath(moon)
ctx.setFillColor(CGColor(red: 0.972, green: 0.925, blue: 0.815, alpha: 1))
ctx.fillPath(using: .evenOdd)
ctx.restoreGState()

// 5. 月牙内部柔和高光（凸面左下更亮）
ctx.saveGState()
ctx.addPath(moon)
ctx.clip(using: .evenOdd)
let rimColors = [
    CGColor(red: 1.0, green: 0.985, blue: 0.94, alpha: 0.95),
    CGColor(red: 0.96, green: 0.88, blue: 0.72, alpha: 0.15),
    CGColor(red: 0.90, green: 0.80, blue: 0.95, alpha: 0.0),
] as CFArray
let rim = CGGradient(colorsSpace: cs, colors: rimColors, locations: [0, 0.5, 1])!
ctx.drawRadialGradient(
    rim,
    startCenter: CGPoint(x: moonC.x - 150, y: moonC.y - 130), startRadius: 0,
    endCenter: CGPoint(x: moonC.x - 50, y: moonC.y - 60), endRadius: 430,
    options: [.drawsBeforeStartLocation]
)
ctx.restoreGState()

// 6. 地平线：极淡的夜雾，增加层次
let hazeColors = [
    CGColor(red: 0.55, green: 0.58, blue: 0.95, alpha: 0.16),
    CGColor(red: 0.55, green: 0.58, blue: 0.95, alpha: 0.0),
] as CFArray
let haze = CGGradient(colorsSpace: cs, colors: hazeColors, locations: [0, 1])!
ctx.drawLinearGradient(
    haze,
    start: CGPoint(x: S / 2, y: 150),
    end: CGPoint(x: S / 2, y: 430),
    options: []
)

// 输出 PNG
guard let img = ctx.makeImage() else { exit(2) }
let url = URL(fileURLWithPath: outPath)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { exit(3) }
CGImageDestinationAddImage(dest, img, nil)
if !CGImageDestinationFinalize(dest) { exit(4) }
print("wrote \(outPath)")
