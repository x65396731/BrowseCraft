import Foundation
import GoogleMobileAds

// 中文注释：Sources 页面用于手动触发一次激励广告加载和展示的 SwiftUI 状态模型。
@MainActor
final class RewardedAdTestViewModel: NSObject, ObservableObject, FullScreenContentDelegate {
    @Published private(set) var isLoading: Bool = false
    @Published var message: String?

    private var rewardedAd: RewardedAd?

    func loadAndShow() async {
        guard self.isLoading == false else {
            return
        }

        guard AppAdConfiguration.hasAdMobApplicationID else {
            self.message = "GADApplicationIdentifier is missing. Regenerate the Xcode project from project.yml first."
            return
        }

        let adUnitID: String = AppAdConfiguration.rewardedAdUnitID
        guard adUnitID.isEmpty == false else {
            self.message = "Rewarded ad unit ID is empty for \(AppAdConfiguration.environmentName)."
            return
        }

        self.isLoading = true
        self.message = nil

        do {
            let ad: RewardedAd = try await RewardedAd.load(
                with: adUnitID,
                request: Request()
            )
            ad.fullScreenContentDelegate = self
            self.rewardedAd = ad
            self.isLoading = false
            self.present(ad)
        } catch {
            self.isLoading = false
            self.rewardedAd = nil
            self.message = "Rewarded ad failed to load: \(error.localizedDescription)"
        }
    }

    private func present(_ ad: RewardedAd) {
        ad.present(from: nil) { [weak self, weak ad] in
            let rewardText: String
            if let reward = ad?.adReward {
                rewardText = "\(reward.amount) \(reward.type)"
            } else {
                rewardText = "unknown reward"
            }

            Task { @MainActor in
                self?.message = "Reward earned: \(rewardText)"
            }
        }
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        self.rewardedAd = nil
    }

    func ad(
        _ ad: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        self.rewardedAd = nil
        self.message = "Rewarded ad failed to present: \(error.localizedDescription)"
    }
}
