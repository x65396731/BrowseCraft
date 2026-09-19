import Observation
import Foundation

// 中文注释：AdPlaybackViewModel 用于手动触发一次广告加载和播放。
@MainActor
@Observable
final class AdPlaybackViewModel {
    private(set) var isLoading: Bool = false
    var message: String?

    private let presenter: RewardedAdPresenter = RewardedAdPresenter()

    func loadAndShow() async {
        guard self.isLoading == false else {
            return
        }

        self.isLoading = true
        self.message = nil
        let result: RewardedAdPresentationResult = await self.presenter.present()
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
