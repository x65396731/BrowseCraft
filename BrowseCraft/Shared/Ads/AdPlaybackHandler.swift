import SwiftUI

// 中文注释：AdPlaybackHandler 让 SwiftUI 页面以同一套防重复逻辑响应 shouldPlayAd。
struct AdPlaybackHandler: ViewModifier {
    let shouldPlayAd: Bool
    let markHandled: () -> Void

    @StateObject private var presenter: RewardedAdPresenter = RewardedAdPresenter()

    func body(content: Content) -> some View {
        content
            .task(id: self.shouldPlayAd) {
                guard self.shouldPlayAd else {
                    return
                }

                #if DEBUG
                print("[BrowseCraftAdPlayback] handler received shouldPlayAd=true")
                #endif

                if self.presenter.isPresenting {
                    #if DEBUG
                    print("[BrowseCraftAdPlayback] handler skipped because ad is already presenting")
                    #endif
                    self.markHandled()
                    return
                }

                let result: RewardedAdPresentationResult = await self.presenter.present()
                #if DEBUG
                print("[BrowseCraftAdPlayback] handler presentation finished result=\(result.debugDescription)")
                #endif
                self.markHandled()
            }
    }
}

extension View {
    func handlesRewardedAdPlayback(
        shouldPlayAd: Bool,
        markHandled: @escaping () -> Void
    ) -> some View {
        return self.modifier(
            AdPlaybackHandler(
                shouldPlayAd: shouldPlayAd,
                markHandled: markHandled
            )
        )
    }
}
