import SwiftUI

/// 激励广告与 coin 的接点（设计书 30.5）：广告请求要带已登录用户的标识给 AdMob 服务端验证，
/// 看完后由服务端记账、App 只去刷新余额。播放器与阅读页的广告修饰器从环境里取它；
/// 实现是 Application 层的 `CoinWalletStore`，由根视图注入。
@MainActor
protocol RewardedAdRewardCoordinating: AnyObject, Sendable {
    /// 已登录时返回要写进 `ServerSideVerificationOptions.userIdentifier` 的标识；未登录返回 nil。
    func rewardedAdUserIdentifier() async -> String?
    /// 广告已获得奖励；`userIdentifier` 是本次请求带上的那个（nil 即未登录看的）。
    func rewardedAdCompleted(userIdentifier: String?)
}

private struct RewardedAdRewardCoordinatorKey: EnvironmentKey {
    static let defaultValue: (any RewardedAdRewardCoordinating)? = nil
}

extension EnvironmentValues {
    var rewardedAdRewardCoordinator: (any RewardedAdRewardCoordinating)? {
        get { self[RewardedAdRewardCoordinatorKey.self] }
        set { self[RewardedAdRewardCoordinatorKey.self] = newValue }
    }
}
