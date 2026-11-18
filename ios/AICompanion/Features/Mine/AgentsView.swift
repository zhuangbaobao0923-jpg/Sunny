import SwiftUI

/// 高光时刻 · 全部智能体
struct AgentsView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: "高光时刻", onBack: { dismiss() }) {
                Button {
                    // 去创作页：先退出当前栈，避免下次切回「我的」又停在这个列表
                    router.minePath.removeAll()
                    withAnimation(Motion.quick) { router.tab = .create }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("新建")
                            .font(Typo.body(12.5, weight: .medium))
                    }
                    .foregroundStyle(Palette.gold)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .overlay(Capsule().stroke(Palette.gold.opacity(0.45), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("全部智能体")
                            .font(Typo.display(19))
                            .tracking(1.2)
                            .foregroundStyle(Palette.ink)
                        Text("\(store.myAgents.count)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Palette.gold)
                        Spacer()
                        Text("点卡片进入对话")
                            .font(Typo.body(11))
                            .foregroundStyle(Palette.ink3)
                    }

                    if store.myAgents.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 28, weight: .light))
                                .foregroundStyle(Palette.gold.opacity(0.6))
                            Text("还没有创建过智能体")
                                .font(Typo.body(13.5))
                                .foregroundStyle(Palette.ink3)
                            Button {
                                router.minePath.removeAll()
                                withAnimation(Motion.quick) { router.tab = .create }
                            } label: {
                                Text("去创建第一个")
                                    .font(Typo.body(13, weight: .medium))
                                    .foregroundStyle(Palette.gold)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 8)
                                    .overlay(Capsule().stroke(Palette.gold.opacity(0.5), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 70)
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(store.myAgents) { agent in
                                AgentCardView(agent: agent, imageHeight: 160) {
                                    let character = store.chatCharacter(for: agent)
                                    router.push(.chat(character.id))
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 100)
            }
            .scrollIndicators(.hidden)
        }
        .background(Palette.canvas)
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
    }
}
