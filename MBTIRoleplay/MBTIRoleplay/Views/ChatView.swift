import SwiftUI

struct ChatView: View {
    let character: RoleCharacter

    @Environment(AppStore.self) private var store
    @State private var draft: String = ""
    @FocusState private var inputFocused: Bool

    private var messages: [ChatMessage] {
        store.messages(for: character.id)
    }

    private var isTyping: Bool {
        store.typing.contains(character.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        personaIntro
                        ForEach(messages) { message in
                            MessageBubble(message: message, character: character)
                                .id(message.id)
                        }
                        if isTyping {
                            TypingBubble(character: character)
                                .id("typing")
                        }
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .onAppear {
                    store.markRead(character.id)
                    scrollToBottom(proxy, animated: false)
                }
                .onChange(of: messages.count) { _, _ in
                    scrollToBottom(proxy, animated: true)
                }
                .onChange(of: isTyping) { _, _ in
                    scrollToBottom(proxy, animated: true)
                }
            }

            inputBar
        }
        .background(Theme.bg)
        .navigationTitle(character.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 6) {
                    PersonaChip(persona: character.persona, compact: true)
                    IntimacyDots(level: character.intimacy)
                }
            }
        }
    }

    private var personaIntro: some View {
        VStack(spacing: 8) {
            AvatarView(character: character, size: 64)
            Text(character.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.ink3)
            Text(character.tagline)
                .font(.system(size: 13))
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("说点什么…", text: $draft, axis: .vertical)
                .font(.system(size: 15))
                .lineLimit(1...4)
                .focused($inputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Theme.line, lineWidth: 0.8)
                )

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle().fill(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                      ? Theme.ink3.opacity(0.45)
                                      : Theme.accent)
                    )
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(
            Theme.bg
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Theme.line)
                        .frame(height: 0.8)
                }
        )
    }

    private func send() {
        let text = draft
        draft = ""
        store.send(text, to: character)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        let action = {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
        if animated {
            withAnimation(.easeOut(duration: 0.25)) { action() }
        } else {
            action()
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    let character: RoleCharacter

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isUser {
                Spacer(minLength: 40)
            } else {
                AvatarView(character: character, size: 30)
            }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                if !message.isUser {
                    Text("\(character.name) · \(character.persona.code)")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.ink3)
                }

                Text(message.text)
                    .font(.system(size: 15))
                    .foregroundStyle(message.isUser ? .white : Theme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(message.isUser ? Theme.accent : Theme.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(message.isUser ? Color.clear : Theme.line, lineWidth: 0.8)
                    )

                Text(message.time.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.ink3.opacity(0.8))
            }

            if message.isUser {
                // 用户消息不显示头像，保持右侧干净
            } else {
                Spacer(minLength: 40)
            }
        }
    }
}

struct TypingBubble: View {
    let character: RoleCharacter
    @State private var phase: Int = 0

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            AvatarView(character: character, size: 30)
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Theme.ink3.opacity(index == phase ? 0.85 : 0.3))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.line, lineWidth: 0.8)
            )
            Spacer(minLength: 40)
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { _ in
                Task { @MainActor in
                    phase = (phase + 1) % 3
                }
            }
        }
    }
}
