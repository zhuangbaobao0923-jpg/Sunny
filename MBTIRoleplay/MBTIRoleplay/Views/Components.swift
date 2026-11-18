import SwiftUI

struct AvatarView: View {
    let character: RoleCharacter
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            Theme.avatarGradient(character.paletteIndex)
            Text(character.initial)
                .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.36, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if character.intimacy >= 4 {
                Image(systemName: "heart.fill")
                    .font(.system(size: size * 0.2))
                    .foregroundStyle(Theme.warm)
                    .padding(3)
                    .background(Circle().fill(.white))
                    .offset(x: 3, y: 3)
            }
        }
    }
}

struct PersonaChip: View {
    let persona: MBTIType
    var compact: Bool = false

    var body: some View {
        Text(persona.code)
            .font(.system(size: compact ? 10 : 11, weight: .semibold, design: .rounded))
            .tracking(0.4)
            .foregroundStyle(persona.tone)
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, compact ? 2 : 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(persona.tone.opacity(0.1))
            )
    }
}

struct IntimacyDots: View {
    let level: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                Circle()
                    .fill(index < level ? Theme.warm.opacity(0.8) : Theme.line)
                    .frame(width: 4, height: 4)
            }
        }
    }
}

struct UnreadBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .frame(minWidth: 18, minHeight: 18)
            .background(Capsule().fill(Theme.warm))
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.ink3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
