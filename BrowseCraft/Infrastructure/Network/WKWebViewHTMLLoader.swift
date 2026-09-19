import BrowseCraftCore
import BrowseCraftDomain
import Foundation
import WebKit

// 中文注释：WKWebViewHTMLLoader.swift 负责把需要 JS 渲染的页面加载成最终 HTML，再交给原有解析器。

/// 中文注释：WebView 渲染失败时提供明确错误，方便区分 URL、导航和 DOM 读取问题。
enum WKWebViewHTMLLoaderError: LocalizedError {
    case emptyHTML(url: URL)
    case unexpectedJavaScriptResult(url: URL)
    case timedOut(url: URL, seconds: Double)
    case challengeInterstitialUnresolved(url: URL, seconds: Double)

    var errorDescription: String? {
        switch self {
        case .emptyHTML(let url):
            return "WebView rendered empty HTML: \(url.absoluteString)"
        case .unexpectedJavaScriptResult(let url):
            return "WebView returned unexpected JavaScript result: \(url.absoluteString)"
        case .timedOut(let url, let seconds):
            return "WebView rendering timed out after \(seconds) seconds: \(url.absoluteString)"
        case .challengeInterstitialUnresolved(let url, let seconds):
            return "WebView still showed an anti-bot challenge interstitial after \(seconds) seconds: \(url.absoluteString)"
        }
    }
}

/// 中文注释：真实 WKWebView 实现；仅用于规则标记 needsWebView 的页面内容获取。
final class WKWebViewHTMLLoader: RenderedPageContentLoader, @unchecked Sendable {
    private let credentialProvider: any SourceCredentialProviding
    private let browserRequestHeaderProvider: any BrowserRequestHeaderProviding
    private let systemCookieHeaderProvider: any SystemCookieHeaderProviding
    /// 中文注释：DOM 稳定判定策略由装配点显式声明，不再是本文件里的私有常量（见 WKWebViewDOMStability.swift）。
    private let domStabilityPolicy: WKWebViewDOMStabilityPolicy

    init(
        credentialProvider: any SourceCredentialProviding = EmptySourceCredentialProvider(),
        browserRequestHeaderProvider: any BrowserRequestHeaderProviding = EmptyBrowserRequestHeaderProvider(),
        systemCookieHeaderProvider: any SystemCookieHeaderProviding = EmptySystemCookieHeaderProvider(),
        domStabilityPolicy: WKWebViewDOMStabilityPolicy
    ) {
        self.credentialProvider = credentialProvider
        self.browserRequestHeaderProvider = browserRequestHeaderProvider
        self.systemCookieHeaderProvider = systemCookieHeaderProvider
        self.domStabilityPolicy = domStabilityPolicy
    }

    @MainActor
    func loadRenderedContent(_ request: PageLoadRequest) async throws -> PageContentResponse {
        let operation: WKWebViewHTMLLoadOperation = WKWebViewHTMLLoadOperation(
            url: request.url,
            request: request.requestConfig,
            context: request.sourceContext,
            readinessSelector: request.readinessSelector,
            settleCondition: request.settleCondition,
            credentialProvider: self.credentialProvider,
            browserRequestHeaderProvider: self.browserRequestHeaderProvider,
            systemCookieHeaderProvider: self.systemCookieHeaderProvider,
            domStabilityPolicy: self.domStabilityPolicy
        )

        return try await operation.load()
    }
}

/// 中文注释：只为用例暴露两个计时取值——`APP-MEMO-016` 的不变量「安定上限 < 声明条件时的总超时」
/// 必须能被固定输入钉住，而 `Timing` 是加载操作的私有实现细节。这里不复制取值，直接转发。
enum WKWebViewHTMLLoaderTimingProbe {
    static var settleConditionTimeoutSeconds: Double {
        return WKWebViewHTMLLoadOperation.settleConditionTimeoutSecondsForTests
    }

    static var defaultTimeoutSeconds: Double {
        return WKWebViewHTMLLoadOperation.defaultTimeoutSecondsForTests
    }
}

@MainActor
final class WKWebViewHTMLLoadOperation: NSObject, WKNavigationDelegate {
    private enum Timing {
        static let defaultTimeoutNanoseconds: UInt64 = 12_000_000_000
        static let defaultTimeoutSeconds: Double = 12
        static let autoScrollTimeoutNanoseconds: UInt64 = 24_000_000_000
        static let autoScrollTimeoutSeconds: Double = 24
        /// 中文注释：声明了结构安定条件（`APP-MEMO-016`）时的总超时。它必须**严格大于**安定条件自己的上限，
        /// 否则等待还没交卷、外层就按超时把当前 DOM 交出去——2026-09-18 真机日志同时出现
        /// 「timeout after 12.0s, using current DOM」与「dom-stability reason=settled waitedMs=11397」，
        /// 就是两者同为 12 s 撞在一起。余量取 5 s，与规则生成引擎同构（谓词上限 12 s、crawl4ai 超时 17 s）。
        static let settleConditionTimeoutSeconds: Double = 17
        static let settleConditionTimeoutNanoseconds: UInt64 = 17_000_000_000
        static let postFinishDelayNanoseconds: UInt64 = 500_000_000
        static let postScrollDelayNanoseconds: UInt64 = 500_000_000
    }

    nonisolated static var settleConditionTimeoutSecondsForTests: Double {
        return Timing.settleConditionTimeoutSeconds
    }

    nonisolated static var defaultTimeoutSecondsForTests: Double {
        return Timing.defaultTimeoutSeconds
    }

    private let url: URL
    private let request: RequestConfig?
    private let context: SourceRequestContext?
    private let readinessSelector: String?
    private let settleCondition: PageContentSettleCondition?
    private let credentialProvider: any SourceCredentialProviding
    private let browserRequestHeaderProvider: any BrowserRequestHeaderProviding
    private let systemCookieHeaderProvider: any SystemCookieHeaderProviding
    private let domStabilityPolicy: WKWebViewDOMStabilityPolicy
    private let webView: WKWebView
    private var continuation: CheckedContinuation<PageContentResponse, Error>?
    private var hasCompleted: Bool = false
    private var isLoadingHTTPSUpgrade: Bool = false
    private var timeoutTask: Task<Void, Never>?
    // 中文注释：`BC-EVIDENCE-081`——过渡页 / 文档决策只消费这个状态机。
    private var challengeGate: WKWebViewChallengeInterstitialGate = WKWebViewChallengeInterstitialGate()

    init(
        url: URL,
        request: RequestConfig?,
        context: SourceRequestContext?,
        readinessSelector: String?,
        settleCondition: PageContentSettleCondition?,
        credentialProvider: any SourceCredentialProviding,
        browserRequestHeaderProvider: any BrowserRequestHeaderProviding,
        systemCookieHeaderProvider: any SystemCookieHeaderProviding,
        domStabilityPolicy: WKWebViewDOMStabilityPolicy
    ) {
        self.url = url
        self.request = request
        self.context = context
        self.readinessSelector = readinessSelector
        self.settleCondition = settleCondition
        self.credentialProvider = credentialProvider
        self.browserRequestHeaderProvider = browserRequestHeaderProvider
        self.systemCookieHeaderProvider = systemCookieHeaderProvider
        self.domStabilityPolicy = domStabilityPolicy

        let configuration: WKWebViewConfiguration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        self.webView = WKWebView(frame: .zero, configuration: configuration)

        super.init()

        self.webView.navigationDelegate = self
    }

    /// 中文注释：用 checked continuation 把 WKNavigationDelegate 生命周期桥接到 async/await。
    func load() async throws -> PageContentResponse {
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let urlRequest: URLRequest = self.urlRequest(for: self.url, includeBody: true)
                self.applyUserAgent(from: urlRequest)
                self.prepareCookieStore(from: urlRequest) {
                    guard self.hasCompleted == false else {
                        return
                    }
                    self.webView.load(urlRequest)
                }
                self.startTimeout()
            }
        } onCancel: {
            Task { @MainActor in
                self.finish(.failure(CancellationError()))
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        self.isLoadingHTTPSUpgrade = false
        Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: Timing.postFinishDelayNanoseconds)

                if self.request?.autoScroll == true {
                    try await self.scrollToBottom()
                    try await Task.sleep(nanoseconds: Timing.postScrollDelayNanoseconds)
                }

                try await self.waitForStableDOM()
                let html: String = try await self.renderedHTML()
                guard self.hasCompleted == false else {
                    return
                }
                // 中文注释：`BC-EVIDENCE-081`——挑战过渡页不是文档。Cloudflare JS 挑战先以一份
                // 稳定 DOM 完成首次导航，脚本跑完后才二次导航到真页；这里不返回过渡页，
                // 只在首次检测时把时限一次性延长，然后等待下一次 didFinish 复判。
                switch self.challengeGate.evaluate(renderedHTML: html) {
                case .document:
                    self.finish(.success(self.response(for: html)))
                case .waitForNextNavigation(let extendTimeoutSeconds):
                    if let seconds: Double = extendTimeoutSeconds {
                        #if DEBUG
                        AppDebugLog.write(
                            "[BrowseCraftWebView] challenge interstitial observed, waiting up to " +
                            "\(seconds)s url=\(self.url.absoluteString)"
                        )
                        #endif
                        self.startTimeout(
                            nanoseconds: UInt64(seconds * 1_000_000_000),
                            seconds: seconds
                        )
                    }
                }
            } catch {
                self.finish(.failure(error))
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard navigationAction.targetFrame?.isMainFrame == true,
              let navigationURL: URL = navigationAction.request.url,
              let upgradedURL: URL = self.httpsURLIfNeeded(from: navigationURL) else {
            return .allow
        }

        self.isLoadingHTTPSUpgrade = true
        let upgradedRequest: URLRequest = self.urlRequest(for: upgradedURL, includeBody: false)
        self.applyUserAgent(from: upgradedRequest)
        webView.load(upgradedRequest)
        return .cancel
    }

    private func startTimeout() {
        self.startTimeout(
            nanoseconds: self.timeoutNanoseconds,
            seconds: self.timeoutSeconds
        )
    }

    private func startTimeout(nanoseconds: UInt64, seconds: Double) {
        self.timeoutTask?.cancel()
        self.timeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard let self else {
                return
            }
            await self.finishAfterTimeout(seconds: seconds)
        }
    }

    /// 中文注释：`didFinish` 等的是整页子资源——漫画阅读页动辄几十张分镜图，移动网络下 12 秒
    /// 常常还没下完，而 DOM 早就齐了（`<img src>` 不需要图片下载完才存在）。2026-09-13 真机：
    /// manmanapp 53 张图的章节两次超时、32 张的那章能过。到时限时先把当前 DOM 拿出来，
    /// 是真页就按成功交出去；只有拿不到 DOM、或仍在挑战过渡页时才报超时。
    private func finishAfterTimeout(seconds: Double) async {
        guard self.hasCompleted == false else {
            return
        }
        if self.challengeGate.challengeInterstitialObserved == false,
           let html: String = try? await self.renderedHTML(),
           case .document = self.challengeGate.evaluate(renderedHTML: html) {
            #if DEBUG
            AppDebugLog.write(
                "[BrowseCraftWebView] timeout after \(seconds)s, using current DOM " +
                "length=\(html.count) url=\(self.url.absoluteString)"
            )
            #endif
            self.finish(.success(self.response(for: html)))
            return
        }
        self.finish(
            .failure(self.challengeGate.timeoutError(url: self.url, seconds: seconds))
        )
    }

    private var timeoutNanoseconds: UInt64 {
        if self.request?.autoScroll == true {
            return Timing.autoScrollTimeoutNanoseconds
        }
        // 中文注释：声明了结构安定条件的请求要给等待留余量，见 `Timing.settleConditionTimeoutSeconds`。
        return self.settleCondition == nil
            ? Timing.defaultTimeoutNanoseconds
            : Timing.settleConditionTimeoutNanoseconds
    }

    private var timeoutSeconds: Double {
        if self.request?.autoScroll == true {
            return Timing.autoScrollTimeoutSeconds
        }
        return self.settleCondition == nil
            ? Timing.defaultTimeoutSeconds
            : Timing.settleConditionTimeoutSeconds
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: Error) {
        guard self.shouldIgnoreInterruptedNavigation(error) == false else {
            return
        }

        self.finish(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: Error) {
        guard self.shouldIgnoreInterruptedNavigation(error) == false else {
            return
        }

        self.finish(.failure(error))
    }

    /// `BC-ACQ-044` 的请求头轴在 WKWebView 路径上要靠 `customUserAgent` 才成立。
    ///
    /// 中文注释：**WebKit 会用自己的 UA 覆盖 `URLRequest` 上的 `User-Agent`**，
    /// 所以 `urlRequest(for:)` 里 `setValue` 的那一行对渲染路径是无效的——只有
    /// `customUserAgent` 能改。设计书 23.6 当初写下的「App 两条路发出的都是规则里那个串」
    /// 对 URLSession 成立、对这条路不成立，当时没有实测渲染路径。
    ///
    /// 2026-09-19 真机逮到：`BC-ACQ-059` 把采集面换成桌面 UA 之后，引擎在 178 的阅读页上
    /// 学到桌面模板选择器 `div.comicpage img`（同一章节页桌面 76 KB / 35 张图），
    /// 而 WKWebView 仍发 iOS Safari UA、拿到移动模板（15.7 KB，容器是 `div#cp_img`），
    /// 于是 `dom-stability matched=40` 但 `pageCount=0`、`selectorEmpty`。
    /// 改之前两边**碰巧**一致（引擎也用 iPhone UA），不是设计如此。
    private func applyUserAgent(from urlRequest: URLRequest) {
        let userAgent: String? = urlRequest.allHTTPHeaderFields?.first { key, _ in
            key.caseInsensitiveCompare("User-Agent") == .orderedSame
        }?.value
        // 中文注释：取不到就不动——保持 WKWebView 自己的 UA，与本改动之前逐字相同。
        guard let userAgent: String, userAgent.isEmpty == false else {
            return
        }
        self.webView.customUserAgent = userAgent
    }

    /// 中文注释：WebView 使用同一份 RequestConfig header/body 语义，避免 HTTP 与 WebView 路径请求差异过大。
    private func urlRequest(for url: URL, includeBody: Bool) -> URLRequest {
        var urlRequest: URLRequest = URLRequest(url: url)
        urlRequest.httpMethod = self.request?.method?.rawValue ?? "GET"

        let headers: [String: String] = RequestHeaderFields.applyingOverrides(
            self.request?.headers,
            to: self.browserRequestHeaderProvider.defaultHeaders(for: url)
        )
        headers.forEach { key, value in
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        let cookieHeaders: [String: String] = CookieHeaderResolver.headersByApplyingPageCookies(
            to: urlRequest.allHTTPHeaderFields ?? [:],
            url: url,
            request: self.request,
            browserCookieHeader: self.systemCookieHeaderProvider.cookieHeader(for: url),
            credentialCookieHeader: self.context.flatMap {
                self.credentialProvider.cookieHeader(for: $0, url: url)
            }
        )
        cookieHeaders.forEach { key, value in
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        if includeBody, let body: RequestBody = self.request?.body {
            urlRequest.httpBody = Data(body.value.utf8)
            if let contentType: String = body.contentType {
                urlRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
            }
        }

        return urlRequest
    }

    /// 中文注释：Source credential Cookie 先写入 WebKit store，保证 JS/iframe/媒体子请求与首个文档请求共享登录态。
    private func prepareCookieStore(
        from request: URLRequest,
        completion: @escaping @MainActor () -> Void
    ) {
        guard let url: URL = request.url,
              let host: String = url.host,
              let cookieHeader: String = request.value(forHTTPHeaderField: "Cookie") else {
            completion()
            return
        }
        let cookies: [HTTPCookie] = cookieHeader.split(separator: ";").compactMap { component in
            let pair: [Substring] = component.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else {
                return nil
            }
            let name: String = pair[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value: String = pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.isEmpty == false else {
                return nil
            }
            var properties: [HTTPCookiePropertyKey: Any] = [
                .domain: host,
                .path: "/",
                .name: name,
                .value: value
            ]
            if url.scheme?.lowercased() == "https" {
                properties[.secure] = "TRUE"
            }
            return HTTPCookie(properties: properties)
        }
        guard cookies.isEmpty == false else {
            completion()
            return
        }
        let cookieStore: WKHTTPCookieStore = self.webView.configuration.websiteDataStore.httpCookieStore
        let group: DispatchGroup = DispatchGroup()
        for cookie: HTTPCookie in cookies {
            group.enter()
            cookieStore.setCookie(cookie) {
                group.leave()
            }
        }
        group.notify(queue: .main) {
            Task { @MainActor in
                completion()
            }
        }
    }

    private func httpsURLIfNeeded(from url: URL) -> URL? {
        guard url.scheme?.lowercased() == "http",
              var components: URLComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.scheme = "https"
        return components.url
    }

    private func shouldIgnoreInterruptedNavigation(_ error: Error) -> Bool {
        guard self.isLoadingHTTPSUpgrade else {
            return false
        }

        let nsError: NSError = error as NSError
        return (nsError.domain == "WebKitErrorDomain" && nsError.code == 102)
            || (nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled)
    }

    /// 中文注释：部分懒加载站点需要真实滚动节奏才会把下方图片写入 DOM。
    private func scrollToBottom() async throws {
        var previousY: Double = -1

        for step in 0..<10 {
            let result: Any? = try await self.webView.evaluateJavaScript(
                """
                (() => {
                  const viewport = window.innerHeight || 667;
                  const targetY = Math.min(
                    document.body.scrollHeight,
                    Math.round(\(step + 1) * viewport * 0.85)
                  );
                  window.scrollTo(0, targetY);
                  window.dispatchEvent(new Event("scroll"));
                  return {
                    y: window.scrollY,
                    viewport: viewport,
                    height: document.body.scrollHeight
                  };
                })();
                """
            )
            let state: [String: Any] = result as? [String: Any] ?? [:]
            let currentY: Double = self.doubleValue(state["y"])
            let viewport: Double = self.doubleValue(state["viewport"])
            let height: Double = self.doubleValue(state["height"])

            try await Task.sleep(nanoseconds: 180_000_000)
            if abs(currentY - previousY) < 4,
               currentY + viewport >= height - 4 {
                break
            }

            previousY = currentY
        }
    }

    private func doubleValue(_ value: Any?) -> Double {
        if let double: Double = value as? Double {
            return double
        }

        if let int: Int = value as? Int {
            return Double(int)
        }

        return 0
    }

    private func waitForStableDOM() async throws {
        let waiter: WKWebViewDOMStabilityWaiter = WKWebViewDOMStabilityWaiter(
            policy: self.domStabilityPolicy,
            url: self.url
        )
        let outcome: WKWebViewDOMStabilityWaiter.Outcome = try await waiter.waitForStableDOM(
            in: self.webView,
            readinessSelector: self.readinessSelector,
            settleCondition: self.settleCondition
        )
        #if DEBUG
        AppDebugLog.write(
            "[BrowseCraftWebView] dom-stability reason=\(outcome.reason.rawValue) " +
            "waitedMs=\(outcome.waited.milliseconds) checks=\(outcome.observedChecks) " +
            "selector=\(self.readinessSelector == nil ? "none" : "declared") " +
            "settleCondition=\(self.settleCondition?.rawValue ?? "none") " +
            "matched=\(outcome.matchedCount.map(String.init) ?? "-") " +
            "url=\(self.url.absoluteString)"
        )
        #endif
    }

    /// 中文注释：didFinish 与 DOM 稳定检查完成后读取整页 DOM；正文为空仍是合法页面结果，
    /// 由上层规则决定 empty 的业务语义。
    private func renderedHTML() async throws -> String {
        let result: Any? = try await self.webView.evaluateJavaScript(
            "document.documentElement.outerHTML"
        )

        guard let html: String = result as? String else {
            throw WKWebViewHTMLLoaderError.unexpectedJavaScriptResult(url: self.url)
        }

        guard html.isEmpty == false else {
            throw WKWebViewHTMLLoaderError.emptyHTML(url: self.url)
        }

        return html
    }

    private func response(for html: String) -> PageContentResponse {
        return PageContentResponse(
            content: html,
            finalURL: self.webView.url ?? self.url
        )
    }

    private func finish(_ result: Result<PageContentResponse, Error>) {
        guard self.hasCompleted == false else {
            return
        }

        self.hasCompleted = true
        self.timeoutTask?.cancel()
        self.timeoutTask = nil
        self.webView.stopLoading()
        self.webView.navigationDelegate = nil

        switch result {
        case .success(let response):
            self.continuation?.resume(returning: response)
        case .failure(let error):
            self.continuation?.resume(throwing: error)
        }

        self.continuation = nil
    }
}
