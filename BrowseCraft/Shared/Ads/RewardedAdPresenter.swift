import AppTrackingTransparency
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

    /// `userIdentifier`：已登录用户的标识，写进 AdMob 服务端验证（设计书 30.5）；未登录传 nil，
    /// 看完的广告不计 coin。
    func present(userIdentifier: String? = nil) async -> RewardedAdPresentationResult {
        guard self.isPresenting == false else {
            #if DEBUG
            AppDebugLog.write("[BrowseCraftAdPlayback] presenter skipped because isPresenting=true")
            #endif
            return .skipped
        }

        guard AppAdConfiguration.hasAdMobApplicationID else {
            let message: String = "GADApplicationIdentifier is missing."
            self.lastMessage = message
            #if DEBUG
            AppDebugLog.write("[BrowseCraftAdPlayback] presenter unavailable \(message)")
            #endif
            return .unavailable(message)
        }

        let adUnitID: String = AppAdConfiguration.rewardedAdUnitID
        guard adUnitID.isEmpty == false else {
            let message: String = "Rewarded ad unit ID is empty for \(AppAdConfiguration.environmentName)."
            self.lastMessage = message
            #if DEBUG
            AppDebugLog.write("[BrowseCraftAdPlayback] presenter unavailable \(message)")
            #endif
            return .unavailable(message)
        }

        self.isPresenting = true
        self.lastMessage = nil
        self.didEarnReward = false

        await Self.requestTrackingAuthorizationIfNeeded()

        do {
            #if DEBUG
            AppDebugLog.write(
                "[BrowseCraftAdPlayback] presenter loading " +
                "environment=\(AppAdConfiguration.environmentName) adUnitID=\(adUnitID)"
            )
            #endif
            let ad: RewardedAd = try await RewardedAd.load(
                with: adUnitID,
                request: Request()
            )
            ad.fullScreenContentDelegate = self
            if let userIdentifier: String = userIdentifier {
                let options: ServerSideVerificationOptions = ServerSideVerificationOptions()
                options.userIdentifier = userIdentifier
                ad.serverSideVerificationOptions = options
            }
            self.rewardedAd = ad
            #if DEBUG
            AppDebugLog.write("[BrowseCraftAdPlayback] presenter loaded, presenting")
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
                        AppDebugLog.write("[BrowseCraftAdPlayback] presenter reward earned \(rewardText)")
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
            AppDebugLog.write("[BrowseCraftAdPlayback] presenter load failed \(message)")
            #endif
            return .failed(message)
        }
    }

    /// 中文注释：AdMob 自带隐私清单把设备 ID 标成用于跟踪，App Store 隐私标签照此声明（用户 2026-10-17 裁定），
    /// 所以第一次播广告前先问跟踪授权；Google 建议等授权回调结束再加载广告。允许与否都照常加载、照常发 coin
    /// （审核指南 5.1.2(i)：不得拿奖励换跟踪授权）。系统只在 App 活跃时弹窗，这里由用户点击触发，天然满足。
    private static func requestTrackingAuthorizationIfNeeded() async {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else {
            return
        }
        let status: ATTrackingManager.AuthorizationStatus = await ATTrackingManager.requestTrackingAuthorization()
        // 中文注释：真的弹过窗才报；仍是 notDetermined（系统没弹出来）不报，其余拒绝类状态归 restricted。
        switch status {
        case .authorized:
            AppAnalytics.shared.logTrackingAuthorizationResult(.authorized)
        case .denied:
            AppAnalytics.shared.logTrackingAuthorizationResult(.denied)
        case .notDetermined:
            break
        default:
            AppAnalytics.shared.logTrackingAuthorizationResult(.restricted)
        }
        #if DEBUG
        AppDebugLog.write(
            "[BrowseCraftAdPlayback] tracking authorization " +
            "status=\(ATTrackingManager.trackingAuthorizationStatus.rawValue)"
        )
        #endif
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        #if DEBUG
        AppDebugLog.write("[BrowseCraftAdPlayback] presenter dismissed didEarnReward=\(self.didEarnReward)")
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
        AppDebugLog.write("[BrowseCraftAdPlayback] presenter present failed \(message)")
        #endif
        self.finish(result: .failed(message))
    }

    private func finish(result: RewardedAdPresentationResult) {
        #if DEBUG
        AppDebugLog.write("[BrowseCraftAdPlayback] presenter finish result=\(result.debugDescription)")
        #endif
        self.rewardedAd = nil
        self.isPresenting = false
        self.didEarnReward = false
        let continuation: CheckedContinuation<RewardedAdPresentationResult, Never>? = self.continuation
        self.continuation = nil
        continuation?.resume(returning: result)
    }
}
