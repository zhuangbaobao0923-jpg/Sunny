import SwiftUI

struct CharacterCreatorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var title: String = ""
    @State private var persona: MBTIType = .intj
    @State private var tagline: String = ""

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("角色") {
                    TextField("称呼，如「顾言」", text: $name)
                    TextField("身份，如「INTJ 军师」", text: $title)
                }

                Section {
                    Picker("人格类型", selection: $persona) {
                        ForEach(MBTIType.allCases) { type in
                            Text("\(type.code) · \(type.nickname)").tag(type)
                        }
                    }
                } header: {
                    Text("人格内核")
                } footer: {
                    Text("选了人格，说话方式、句长、语气词都会自动对齐，不用写 Prompt。当前：\(persona.voiceProfile)")
                }

                Section("一句话人设") {
                    TextField("他和你相处时是什么样子", text: $tagline, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    HStack {
                        Text("初始亲密度")
                        Spacer()
                        Text("陌生")
                            .foregroundStyle(Theme.ink3)
                    }
                }
            }
            .navigationTitle("捏一个角色")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        store.addCharacter(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            title: title.isEmpty ? "\(persona.code) 角色" : title,
                            persona: persona,
                            tagline: tagline.isEmpty ? persona.oneLiner : tagline
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}
