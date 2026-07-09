import Foundation
import GoogleMobileAds

enum RewardedAdPresentationResult: Equatable {
    case completed
    case skipped
    case unavailable(String)
    case failed(String)

    var debugDescription: String {
        switch self {
        case .completed:
            return "completed"
        case .skipped:
            return "skipped"
        case .unavailable(let message):
            return "unavailable(\(message))"
        case .failed(let message):
            return "failed(\(message))"
        }
    }
}

// 中文注释：RewardedAdPresenter 封装 AdMob 激励广告加载和展示，业务层只关心播放结果。
@MainActor
final class RewardedAdPresenter: NSObject, ObservableObject, FullScreenContentDelegate {
    @Published private(set) var isPresenting: Bool = false
    @Published private(set) var lastMessage: String?

    private var rewardedAd: RewardedAd?
    private var continuation: CheckedContinuation<RewardedAdPresentationResult, Never>?
    private var didEarnReward: Bool = false

    func present() async -> RewardedAdPresentationResult {
        guard self.isPresenting == false else {
            #if DEBUG
            print("[BrowseCraftAdPlayback] presenter skipped because isPresenting=true")
            #endif
            return .skipped
        }

        guard AppAdConfiguration.hasAdMobApplicationID else {
            let message: String = "GADApplicationIdentifier is missing."
            self.lastMessage = message
            #if DEBUG
            print("[BrowseCraftAdPlayback] presenter unavailable \(message)")
            #endif
            return .unavailable(message)
        }

        let adUnitID: String = AppAdConfiguration.rewardedAdUnitID
        guard adUnitID.isEmpty == false else {
            let message: String = "Rewarded ad unit ID is empty for \(AppAdConfiguration.environmentName)."
            self.lastMessage = message
            #if DEBUG
            print("[BrowseCraftAdPlayback] presenter unavailable \(message)")
            #endif
            return .unavailable(message)
        }

        self.isPresenting = true
        self.lastMessage = nil
        self.didEarnReward = false

        do {
            #if DEBUG
            print(
                "[BrowseCraftAdPlayback] presenter loading " +
                "environment=\(AppAdConfiguration.environmentName) adUnitID=\(adUnitID)"
            )
            #endif
            let ad: RewardedAd = try await RewardedAd.load(
                with: adUnitID,
                request: Request()
            )
            ad.fullScreenContentDelegate = self
            self.rewardedAd = ad
            #if DEBUG
            print("[BrowseCraftAdPlayback] presenter loaded, presenting")
            #endif

            return await withCheckedContinuation { continuation in
                self.continuation = continuation
                ad.present(from: nil) { [weak self, weak ad] in
                    let rewardText: String
                    if let reward = ad?.adReward {
                        rewardText = "\(reward.amount) \(reward.type)"
                    } else {
                        rewardText = "unknown reward"
                    }

                    Task { @MainActor in
                        self?.didEarnReward = true
                        self?.lastMessage = "Reward earned: \(rewardText)"
                        #if DEBUG
                        print("[BrowseCraftAdPlayback] presenter reward earned \(rewardText)")
                        #endif
                    }
                }
            }
        } catch {
            self.rewardedAd = nil
            self.isPresenting = false
            let message: String = "Rewarded ad failed to load: \(error.localizedDescription)"
            self.lastMessage = message
            #if DEBUG
            print("[BrowseCraftAdPlayback] presenter load failed \(message)")
            #endif
            return .failed(message)
        }
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        #if DEBUG
        print("[BrowseCraftAdPlayback] presenter dismissed didEarnReward=\(self.didEarnReward)")
        #endif
        self.finish(result: self.didEarnReward ? .completed : .skipped)
    }

    func ad(
        _ ad: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        let message: String = "Rewarded ad failed to present: \(error.localizedDescription)"
        self.lastMessage = message
        #if DEBUG
        print("[BrowseCraftAdPlayback] presenter present failed \(message)")
        #endif
        self.finish(result: .failed(message))
    }

    private func finish(result: RewardedAdPresentationResult) {
        #if DEBUG
        print("[BrowseCraftAdPlayback] presenter finish result=\(result.debugDescription)")
        #endif
        self.rewardedAd = nil
        self.isPresenting = false
        self.didEarnReward = false
        let continuation: CheckedContinuation<RewardedAdPresentationResult, Never>? = self.continuation
        self.continuation = nil
        continuation?.resume(returning: result)
    }
}
