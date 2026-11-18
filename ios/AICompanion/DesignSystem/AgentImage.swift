import SwiftUI

// MARK: - 角色形象图（兼容打包底图与 AI 生成图）

/// imageName 既可能是 Assets 里的底图（如 char_shenjinghan），
/// 也可能是 AI 生成后落盘的绝对路径（Caches/generated-faces/...）。
/// 含「/」按文件图加载，否则按资源名加载。滤镜 hue/saturation 仅对底图有意义。
struct AgentImage: View {
    let name: String
    var hue: Double = 0
    var saturation: Double = 1
    /// .fill = 铺满裁切（列表/背景）；.fit = 显示完整人物（形象确认页）
    var contentMode: ContentMode = .fill

    var body: some View {
        if let file = Self.fileImage(named: name) {
            Image(uiImage: file)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else {
            Image(name)
                .resizable()
                .aspectRatio(contentMode: contentMode)
                .hueRotation(.degrees(hue))
                .saturation(saturation)
        }
    }

    static func fileImage(named name: String) -> UIImage? {
        guard name.contains("/") else { return nil }
        return UIImage(contentsOfFile: name)
    }
}
