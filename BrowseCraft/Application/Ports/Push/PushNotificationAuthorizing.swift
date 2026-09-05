import Foundation

enum PushNotificationAuthorizationStatus: Equatable, Sendable {
    case authorized
    case denied
}

/// 请求用户可见通知权限的 Application 端口。
///
/// 中文注释：服务端推送是 `alert` 类型，没有这项授权横幅不会显示。device token 的获取
/// 不依赖它——`registerForRemoteNotifications()` 在启动时就已调用；这里只管系统提示。
protocol PushNotificationAuthorizing: Sendable {
    /// 只在用户尚未决定时弹系统提示；已经允许或拒绝过则直接返回当前状态。
    func requestAuthorizationIfNeeded() async -> PushNotificationAuthorizationStatus
}
