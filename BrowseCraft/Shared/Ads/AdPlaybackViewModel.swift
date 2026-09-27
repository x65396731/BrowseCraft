import Observation
import Foundation

// 中文注释：AdPlaybackViewModel 用于手动触发一次广告加载和播放。
@MainActor
@Observable
final class AdPlaybackViewModel {
    private(set) var isLoading: Bool = false
    var message: String?

    private let presenter: RewardedAdPresenter = RewardedAdPresenter()

    /// `rewardCoordinator`：设置页的手动入口也要走 coin 链路（设计书 30.5）——已登录时广告请求带用户标识，
    /// 看完后由协调器去刷新余额；不传即只放广告、不计 coin。
    func loadAndShow(rewardCoordinator: (any RewardedAdRewardCoordinating)? = nil) async {
        guard self.isLoading == false else {
            return
        }

        self.isLoading = true
        self.message = nil
        let userIdentifier: String? = await rewardCoordinator?.rewardedAdUserIdentifier()
        let result: RewardedAdPresentationResult = await self.presenter.present(userIdentifier: userIdentifier)
        if case .completed = result {
            rewardCoordinator?.rewardedAdCompleted(userIdentifier: userIdentifier)
        }
        self.isLoading = false
        self.message = Self.message(
            for: result,
            signedIn: userIdentifier != nil,
            rewardAmount: rewardCoordinator?.rewardedAdCoinAmount
        )
    }

    /// 中文注释：看完广告后给用户的提示（三语本地化，用户 2026-09-27）。不再直接显示 SDK 的英文原文
    /// （「Reward earned: 20 coin」、加载失败的错误串）——那些照旧写进调试日志。未登录看完不计 coin，文案要说清楚。
    static func message(
        for result: RewardedAdPresentationResult,
        signedIn: Bool,
        rewardAmount: Int?
    ) -> String {
        switch result {
        case .completed:
            guard signedIn, let rewardAmount: Int = rewardAmount else {
                return NSLocalizedString("ad_reward_requires_sign_in", comment: "看完广告但未登录，不计 coin")
            }
            return String(
                format: NSLocalizedString("ad_reward_granted", comment: "看完广告，获得 N coin"),
                rewardAmount
            )
        case .skipped:
            return NSLocalizedString("ad_playback_dismissed", comment: "广告未看完就关闭")
        case .unavailable:
            return NSLocalizedString("ad_playback_unavailable", comment: "广告服务不可用")
        case .failed:
            return NSLocalizedString("ad_playback_failed", comment: "广告加载或播放失败")
        }
    }
}
