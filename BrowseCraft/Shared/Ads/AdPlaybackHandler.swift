import BrowseCraftLog
import SwiftUI

/// 中文注释：谁触发了这次激励广告（设计书 30.8）。埋点参数 `ad_trigger` 取它的 rawValue。
enum RewardedAdPlaybackTrigger: String, Sendable {
    case comic
    case video
    case book
    case audiobook
    case manual
}

/// 中文注释：一次自动唤起的结局，回给页面的视图模型决定积分怎么处理（30.8）：
/// 看完或用户提前关闭 → 广告播过了，清零积分；没播出来（加载失败 / 无填充 / 服务不可用）或
/// 因为已有广告在播而跳过 → 积分保留，下个计分点再试。
enum RewardedAdPlaybackOutcome: Equatable {
    case presented(RewardedAdPresentationResult)
    case skippedBecauseAlreadyPresenting

    var consumesAdPoints: Bool {
        switch self {
        case .presented(.completed), .presented(.skipped):
            return true
        case .presented(.unavailable), .presented(.failed), .skippedBecauseAlreadyPresenting:
            return false
        }
    }
}

// 中文注释：AdPlaybackHandler 让 SwiftUI 页面以同一套防重复逻辑响应 shouldPlayAd。
// 广告结束后的提示与设置页手动入口共用同一组三语文案（`AdPlaybackViewModel.message`），未登录看完也在这里提示。
struct AdPlaybackHandler: ViewModifier {
    let shouldPlayAd: Bool
    let trigger: RewardedAdPlaybackTrigger
    let markHandled: (RewardedAdPlaybackOutcome) -> Void

    @StateObject private var presenter: RewardedAdPresenter = RewardedAdPresenter()
    @Environment(\.rewardedAdRewardCoordinator) private var rewardCoordinator
    @State private var toastMessage: String?
    @State private var toastDismissTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let toastMessage: String = self.toastMessage {
                    RewardedAdToast(message: toastMessage)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: self.toastMessage)
            .task(id: self.shouldPlayAd) {
                guard self.shouldPlayAd else {
                    return
                }

                #if DEBUG
                AppLog.debug(.ad, "ad-playback-handler-received", [
                    "shouldPlayAd": .text("true"),
                    "trigger": .text("\(self.trigger.rawValue)")
                ])
                #endif

                // 中文注释：演示模式（拍商城截图）不弹广告；按「已有广告在播」处理，积分保留。Release 下 `DemoModeFlag.isEnabled` 恒 false。
                if DemoModeFlag.isEnabled {
                    self.markHandled(.skippedBecauseAlreadyPresenting)
                    return
                }

                if self.presenter.isPresenting {
                    #if DEBUG
                    AppLog.debug(.ad, "ad-playback-handler-skipped-already-presenting")
                    #endif
                    self.markHandled(.skippedBecauseAlreadyPresenting)
                    // 中文注释：登录态要异步取，放到标记处理之后，不拖延页面清掉 shouldPlayAd。
                    let trigger: RewardedAdPlaybackTrigger = self.trigger
                    let rewardCoordinator: (any RewardedAdRewardCoordinating)? = self.rewardCoordinator
                    Task {
                        let signedIn: Bool = await rewardCoordinator?.rewardedAdUserIdentifier() != nil
                        AppAnalytics.shared.logRewardedAdSkippedBusy(trigger: trigger, signedIn: signedIn)
                    }
                    return
                }

                let userIdentifier: String? = await self.rewardCoordinator?.rewardedAdUserIdentifier()
                let result: RewardedAdPresentationResult = await self.presenter.present(userIdentifier: userIdentifier)
                #if DEBUG
                AppLog.debug(.ad, "ad-playback-handler-presentation-finished", [
                    "result": .text("\(result.debugDescription)")
                ])
                #endif
                AppAnalytics.shared.logRewardedAdResult(
                    trigger: self.trigger,
                    result: result,
                    signedIn: userIdentifier != nil
                )
                if case .completed = result {
                    RewardedAdCreditReporter.observe(
                        self.rewardCoordinator?.rewardedAdCompleted(userIdentifier: userIdentifier)
                    )
                }
                self.showToast(
                    AdPlaybackViewModel.message(
                        for: result,
                        signedIn: userIdentifier != nil,
                        rewardAmount: self.rewardCoordinator?.rewardedAdCoinAmount
                    )
                )
                self.markHandled(.presented(result))
            }
    }

    private func showToast(_ message: String) {
        self.toastDismissTask?.cancel()
        self.toastMessage = message
        self.toastDismissTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard Task.isCancelled == false else {
                return
            }
            self.toastMessage = nil
        }
    }
}

/// 中文注释：已登录看完广告后，等余额轮询结束报 `ad_reward_credited`；轮询被取消（结果不明）不报。
/// 轮询在 Application 层（`CoinWalletStore`），那一层不碰埋点，所以由这里接住结果上报。
enum RewardedAdCreditReporter {
    @MainActor
    static func observe(_ pollTask: Task<Bool?, Never>?) {
        guard let pollTask: Task<Bool?, Never> else {
            return
        }
        Task {
            guard let credited: Bool = await pollTask.value else {
                return
            }
            AppAnalytics.shared.logAdRewardCredited(credited ? .credited : .timeout)
        }
    }
}

/// 中文注释：广告结束后的一句轻提示，四秒自动消失；不挡操作。
private struct RewardedAdToast: View {
    let message: String

    var body: some View {
        Text(self.message)
            .font(.subheadline)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.black.opacity(0.78), in: Capsule())
    }
}

extension View {
    func handlesRewardedAdPlayback(
        shouldPlayAd: Bool,
        trigger: RewardedAdPlaybackTrigger,
        markHandled: @escaping (RewardedAdPlaybackOutcome) -> Void
    ) -> some View {
        return self.modifier(
            AdPlaybackHandler(
                shouldPlayAd: shouldPlayAd,
                trigger: trigger,
                markHandled: markHandled
            )
        )
    }
}
