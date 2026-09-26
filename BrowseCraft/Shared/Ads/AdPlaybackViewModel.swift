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
        self.message = self.message(for: result)
    }

    private func message(for result: RewardedAdPresentationResult) -> String {
        switch result {
        case .completed:
            return self.presenter.lastMessage ?? NSLocalizedString("ad_playback_completed", comment: "广告播放完成")
        case .skipped:
            return NSLocalizedString("ad_playback_dismissed", comment: "广告播放被关闭")
        case .unavailable(let message), .failed(let message):
            return message
        }
    }
}
