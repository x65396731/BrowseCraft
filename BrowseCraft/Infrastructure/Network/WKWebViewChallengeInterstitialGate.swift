import BrowseCraftDomain
import Foundation

/// 中文注释：`BC-EVIDENCE-081` 的加载器决策状态机——渲染出的 DOM 是文档还是挑战过渡页。
///
/// 它不依赖 WebKit，可以单独测试；`WKWebViewHTMLLoadOperation` 在每次 `didFinish`
/// 读到 DOM 后只消费这里的决定：
/// - `.document`：把 DOM 当文档返回；
/// - `.waitForNextNavigation(extendTimeoutSeconds:)`：不返回、继续等待挑战脚本触发的下一次主帧
///   导航；只有**首次**观察到过渡页时才携带一次性的时限延长，之后再观察到只继续等待。
struct WKWebViewChallengeInterstitialGate {
    enum Decision: Equatable {
        case document
        case waitForNextNavigation(extendTimeoutSeconds: Double?)
    }

    static let challengeTimeoutSeconds: Double = 30

    private(set) var challengeInterstitialObserved: Bool = false

    mutating func evaluate(renderedHTML html: String) -> Decision {
        guard HTMLChallengeInterstitialDetector.isChallengeInterstitial(html) else {
            return .document
        }
        if self.challengeInterstitialObserved {
            return .waitForNextNavigation(extendTimeoutSeconds: nil)
        }
        self.challengeInterstitialObserved = true
        return .waitForNextNavigation(
            extendTimeoutSeconds: Self.challengeTimeoutSeconds
        )
    }

    /// 时限到期时的失败种类：观察过过渡页 → 挑战未解决；否则普通超时。
    func timeoutError(url: URL, seconds: Double) -> WKWebViewHTMLLoaderError {
        return self.challengeInterstitialObserved
            ? .challengeInterstitialUnresolved(url: url, seconds: seconds)
            : .timedOut(url: url, seconds: seconds)
    }
}
