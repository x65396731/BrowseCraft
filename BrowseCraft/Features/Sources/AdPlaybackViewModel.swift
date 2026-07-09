import Foundation

// 中文注释：Sources 页面用于触发一次广告加载和播放的 SwiftUI 状态模型。
@MainActor
final class AdPlaybackViewModel: ObservableObject {
    @Published private(set) var isLoading: Bool = false
    @Published var message: String?

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
            return self.presenter.lastMessage ?? "Ad playback completed."
        case .skipped:
            return "Ad playback dismissed."
        case .unavailable(let message), .failed(let message):
            return message
        }
    }
}
