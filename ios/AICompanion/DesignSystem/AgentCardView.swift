import SwiftUI

/// 智能体卡片（我的页网格 / 高光时刻全部页共用）
struct AgentCardView: View {
    let agent: MyAgent
    var imageHeight: CGFloat = 132
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    if let imageName = agent.imageName {
                        AgentImage(name: imageName, hue: agent.hue, saturation: agent.saturation)
                    } else {
                        LinearGradient(
                            colors: [Color(hex: 0x2A2438), Color(hex: 0x181A28)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    }
                }
                .frame(height: imageHeight)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(alignment: .topLeading) {
                    if agent.imageName == nil {
                        Text(String(agent.name.prefix(1)))
                            .font(Typo.display(34))
                            .foregroundStyle(Palette.gold.opacity(0.55))
                            .padding(.leading, 14)
                            .padding(.top, 10)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    Text("\(agent.views) 浏览")
                        .font(Typo.body(10))
                        .foregroundStyle(Palette.ink2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Palette.bg.opacity(0.6)))
                        .padding(8)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(agent.name)
                        .font(Typo.body(14.5, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(agent.summary)
                        .font(Typo.body(11.5))
                        .foregroundStyle(Palette.ink3)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Palette.card)
            // 命中区域 = 卡片可见边界，点卡片上方空白不会再误进某个角色
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(Palette.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
