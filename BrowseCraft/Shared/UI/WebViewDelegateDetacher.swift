import WebKit

/// 中文注释：WebUI 的 `EnhancedWKWebView` 不把 App 的协调器直接设成代理，而是塞进它自己的
/// `NavigationDelegateProxy`：代理 `weak` 持有协调器，`responds(to:)` 答「协调器实现了就算实现了」，
/// 再经 `forwardingTarget(for:)` 转发。WebKit 只在 `setNavigationDelegate:` 那一刻查一次
/// `respondsToSelector:` 并缓存；协调器（`@StateObject`）先于 WKWebView 释放后（`fullScreenCover`
/// 关闭动画期间 UIView 还在、页面还在跳转），WebKit 按缓存继续调代理没实现的方法，转发目标已是 nil，
/// 直接 `unrecognized selector` 抛异常（1001 构建崩溃 9BE57DCC：
/// `-[… webView:decidePolicyForNavigationAction:preferences:decisionHandler:]`）。
///
/// 用法：凡经 WebUI `.navigationDelegate(_:)` / `.uiDelegate(_:)` 挂上去的协调器持有一个实例，
/// 在第一个拿到 `webView` 的回调里 `attach(_:)`。协调器释放时本对象随之释放，`deinit` 把两个代理置空：
/// 对 `EnhancedWKWebView` 来说这会重新执行 `super.navigationDelegate = proxy`，WebKit 随之重算缓存，
/// 之后不再调那些转发方法。不在代理层吞调用，是因为 `decisionHandler` 不被调用会触发 WebKit 的
/// completion handler 检查，换成另一种崩溃。
@MainActor
final class WebViewDelegateDetacher {
    private weak var webView: WKWebView?

    init() {}

    func attach(_ webView: WKWebView) {
        self.webView = webView
    }

    deinit {
        // 中文注释：持有者都是 SwiftUI 的 `@StateObject`，释放在主线程；WKWebView 的代理只能在主线程改。
        MainActor.assumeIsolated {
            guard let webView: WKWebView = self.webView else {
                return
            }
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
        }
    }
}
