import Foundation
import Observation

/// 全局通话中枢：让通话实例脱离页面存活。
/// 页面收起（最小化）时通话继续进行，右上角显示悬浮小窗；点小窗回到全屏。
@MainActor
@Observable
final class CallCenter {
    static let shared = CallCenter()

    /// 当前通话实例（nil = 没有通话）
    private(set) var model: VoiceCallModel?
    /// 是否全屏展示（false + model 存在 = 已最小化到悬浮窗）
    var isFullScreen = false

    var isActive: Bool { model != nil }
    var isMinimized: Bool { model != nil && !isFullScreen }

    private init() {}

    /// 发起通话
    func start(chatModel: ChatModel, userName: String) {
        end()
        let call = VoiceCallModel(chatModel: chatModel, userName: userName)
        model = call
        isFullScreen = true
        call.startCall()
    }

    /// 最小化到右上角（不挂断，麦克风与计时照常）
    func minimize() {
        guard model != nil else { return }
        isFullScreen = false
    }

    /// 点悬浮窗恢复全屏
    func expand() {
        guard model != nil else { return }
        isFullScreen = true
    }

    /// 挂断并清理
    func end() {
        model?.hangUp()
        model = nil
        isFullScreen = false
    }
}
