import Foundation

// 中文注释：收藏与历史锁定（`docs/design/Content-Lock-Design.md`）需要的两个端口：
// 设备所有者验证（面容 ID / 触控 ID / 锁屏密码）与开关的本机存储。实现都在 Infrastructure，
// 应用层只认识这里的取值，不认识 LocalAuthentication。

/// 这台设备能用的验证方式；决定设置页行的标题、图标与说明（设计文档第 2.2 节）。
enum DeviceOwnerAuthenticationMethod: Equatable, Sendable {
    case faceID
    case touchID
    case opticID
    /// 没有可用的生物识别（没有硬件或没有录入），只能输锁屏密码。
    case passcode
    /// 连锁屏密码都没有：无法验证，锁定开关禁用。
    case unavailable
}

/// 验证结果。用户取消、未通过、被系统暂时锁住都算没有通过——重试与转密码由系统界面处理（设计文档第四节）。
/// 取消单列只为埋点区分结局（`content_unlock_result`），界面上与 `failed` 同样处理。
enum DeviceOwnerAuthenticationResult: Equatable, Sendable {
    case succeeded
    case failed
    case cancelled
}

protocol DeviceOwnerAuthenticating: Sendable {
    /// 每次调用都重新问系统：用户可能刚在系统设置里录入面容 ID 或设好锁屏密码。
    func availableMethod() -> DeviceOwnerAuthenticationMethod
    /// `reason` 显示在触控 ID 与锁屏密码界面上；面容 ID 用 Info.plist 里的用途说明。
    func authenticate(reason: String) async -> DeviceOwnerAuthenticationResult
}

/// 锁定开关只存在本机，不随 iCloud 同步（设计文档第 2.1 节）。
protocol ContentLockPreferenceStoring: Sendable {
    func isContentLockEnabled() -> Bool
    func setContentLockEnabled(_ enabled: Bool)
}
