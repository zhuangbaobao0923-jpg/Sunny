import XCTest
@testable import AICompanion

/// 身份冲突回归：同名不等于同一个角色
@MainActor
final class IdentityTests: XCTestCase {

    func testSameNamedCloudAgentsKeepDistinctIDs() {
        let a = CloudAgent(id: 1, name: "小助理", tagline: "", persona: "",
                           opening: "", ownerName: "作者A", voiceKind: nil)
        let b = CloudAgent(id: 2, name: "小助理", tagline: "", persona: "",
                           opening: "", ownerName: "作者B", voiceKind: nil)

        let first = Character.cloud(a, index: 0)
        let second = Character.cloud(b, index: 1)

        XCTAssertEqual(first.name, second.name)
        XCTAssertNotEqual(first.id, second.id, "同名云端角色必须有不同 id，否则聊天记录会串")
    }

    /// 本地自定义角色的命名空间不能和云端角色重叠
    func testLocalAndCloudNamespacesDoNotCollide() {
        let cloud = CloudAgent(id: 7, name: "萧玄策", tagline: "", persona: "",
                               opening: "", ownerName: "别人", voiceKind: nil)
        let cloudID = Character.cloud(cloud, index: 0).id
        let localID = AppStore.localAgentID("萧玄策")

        XCTAssertNotEqual(cloudID, localID)
        XCTAssertTrue(cloudID.hasPrefix("cloud-"))
        XCTAssertTrue(localID.hasPrefix("agent-"))
    }

    /// 同一个云端 id 每次都映射到同一个角色 id（重启不丢历史）
    func testCloudIDIsStable() {
        let a = CloudAgent(id: 42, name: "小助理", tagline: "", persona: "",
                           opening: "", ownerName: "作者", voiceKind: nil)
        XCTAssertEqual(Character.cloud(a, index: 0).id, Character.cloud(a, index: 3).id)
    }
}
