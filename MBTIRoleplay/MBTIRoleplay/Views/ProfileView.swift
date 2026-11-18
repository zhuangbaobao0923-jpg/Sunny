import SwiftUI

struct ProfileView: View {
    @Environment(AppStore.self) private var store

    private var totalMessages: Int {
        store.characters.reduce(0) { $0 + store.messages(for: $1.id).count }
    }

    private var closestRole: RoleCharacter? {
        store.characters.max { $0.intimacy < $1.intimacy }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                identityCard
                voiceCard
                statsCard
                settingsCard
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Theme.bg)
        .navigationTitle("我的")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.18))
                        .frame(width: 54, height: 54)
                    Text(store.myType.code)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.myType.nickname)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("亲密度最高的角色 · \(closestRole?.name ?? "暂无")")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
            }

            HStack(spacing: 6) {
                ForEach(store.myType.dimensions, id: \.self) { dimension in
                    Text(dimension)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.white.opacity(0.16)))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.heroGradient)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var voiceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("你的声音画像")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            Text(store.myType.voiceProfile)
                .font(.system(size: 13))
                .foregroundStyle(Theme.ink2)
                .lineSpacing(4)
            Text("人格不只决定说什么，也决定怎么开口。角色的台词都按这组参数生成。")
                .font(.system(size: 11))
                .foregroundStyle(Theme.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var statsCard: some View {
        HStack(spacing: 0) {
            statItem(value: "\(store.characters.count)", label: "角色")
            Divider().frame(height: 28).overlay(Theme.line)
            statItem(value: "\(totalMessages)", label: "消息")
            Divider().frame(height: 28).overlay(Theme.line)
            statItem(value: closestRole?.intimacyLabel ?? "—", label: "最亲密")
        }
        .card()
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.ink3)
        }
        .frame(maxWidth: .infinity)
    }

    private var settingsCard: some View {
        VStack(spacing: 0) {
            settingsRow(icon: "checklist", title: "重新测一次人格", detail: store.myType.code)
            Divider().overlay(Theme.line).padding(.leading, 46)
            settingsRow(icon: "bell", title: "角色主动找我", detail: "已开启")
            Divider().overlay(Theme.line).padding(.leading, 46)
            settingsRow(icon: "lock.shield", title: "对话与记忆", detail: "仅本机")
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.line, lineWidth: 0.8)
        )
    }

    private func settingsRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink2)
                .frame(width: 22)
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink)
            Spacer()
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(Theme.ink3)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.ink3.opacity(0.5))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }
}
