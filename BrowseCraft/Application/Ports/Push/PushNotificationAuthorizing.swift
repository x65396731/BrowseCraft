import Foundation

enum PushNotificationAuthorizationStatus: Equatable, Sendable {
    case authorized
    case denied
    /// 用户还没决定过；只会出现在 `currentAuthorizationStatus()` 里，请求之后不会是它。
    case notDetermined
}

/// 一次请求的结果：当前状态，以及这次是否真的弹了系统提示（已决定过的不弹）。
struct PushNotificationAuthorizationOutcome: Equatable, Sendable {
    let status: PushNotificationAuthorizationStatus
    let didPrompt: Bool
}

/// 请求用户可见通知权限的 Application 端口。
///
/// 中文注释：服务端推送是 `alert` 类型，没有这项授权横幅不会显示。device token 的获取
/// 不依赖它——`registerForRemoteNotifications()` 在启动时就已调用；这里只管系统提示。
protocol PushNotificationAuthorizing: Sendable {
    /// 只在用户尚未决定时弹系统提示；已经允许或拒绝过则直接返回当前状态。
    func requestAuthorizationIfNeeded() async -> PushNotificationAuthorizationOutcome
    /// 只读当前状态、不弹提示：设置页「活动推送」组下说明按它选（Campaign-And-Rate-Notices-Design.md 第四节）。
    func currentAuthorizationStatus() async -> PushNotificationAuthorizationStatus
}
