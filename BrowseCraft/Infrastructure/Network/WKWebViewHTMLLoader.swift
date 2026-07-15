import Foundation
import WebKit

// 中文注释：WKWebViewHTMLLoader.swift 负责把需要 JS 渲染的页面加载成最终 HTML，再交给原有解析器。

/// 中文注释：WebView 渲染失败时提供明确错误，方便区分 URL、导航和 DOM 读取问题。
enum WKWebViewHTMLLoaderError: LocalizedError {
    case emptyHTML(url: URL)
    case unexpectedJavaScriptResult(url: URL)
    case timedOut(url: URL, seconds: Double)

    var errorDescription: String? {
        switch self {
        case .emptyHTML(let url):
            return "WebView rendered empty HTML: \(url.absoluteString)"
        case .unexpectedJavaScriptResult(let url):
            return "WebView returned unexpected JavaScript result: \(url.absoluteString)"
        case .timedOut(let url, let seconds):
            return "WebView rendering timed out after \(seconds) seconds: \(url.absoluteString)"
        }
    }
}

/// 中文注释：真实 WKWebView 实现；仅用于规则标记 needsWebView 的页面内容获取。
final class WKWebViewHTMLLoader: RenderedPageContentLoader {
    @MainActor
    func getRenderedString(from url: URL, request: RequestConfig?) async throws -> String {
        let operation: WKWebViewHTMLLoadOperation = WKWebViewHTMLLoadOperation(
            url: url,
            request: request
        )

        return try await operation.load()
    }
}

@MainActor
private final class WKWebViewHTMLLoadOperation: NSObject, WKNavigationDelegate {
    private enum Timing {
        static let defaultTimeoutNanoseconds: UInt64 = 12_000_000_000
        static let defaultTimeoutSeconds: Double = 12
        static let autoScrollTimeoutNanoseconds: UInt64 = 24_000_000_000
        static let autoScrollTimeoutSeconds: Double = 24
        static let earlySnapshotInitialDelayNanoseconds: UInt64 = 1_200_000_000
        static let earlySnapshotIntervalNanoseconds: UInt64 = 500_000_000
        static let earlySnapshotAttempts: Int = 16
        static let earlySnapshotMinimumHTMLLength: Int = 4_096
        static let postFinishDelayNanoseconds: UInt64 = 500_000_000
        static let postScrollDelayNanoseconds: UInt64 = 500_000_000
        static let domStableDelayNanoseconds: UInt64 = 300_000_000
        static let domStableChecks: Int = 3
        static let stableLengthDelta: Int = 32
    }

    private let url: URL
    private let request: RequestConfig?
    private let webView: WKWebView
    private var continuation: CheckedContinuation<String, Error>?
    private var hasCompleted: Bool = false
    private var isLoadingHTTPSUpgrade: Bool = false

    init(url: URL, request: RequestConfig?) {
        self.url = url
        self.request = request

        let configuration: WKWebViewConfiguration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        self.webView = WKWebView(frame: .zero, configuration: configuration)

        super.init()

        self.webView.navigationDelegate = self
    }

    /// 中文注释：用 checked continuation 把 WKNavigationDelegate 生命周期桥接到 async/await。
    func load() async throws -> String {
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                self.webView.load(self.urlRequest(for: self.url, includeBody: true))
                self.startTimeout()
                self.startEarlySnapshotPollingIfNeeded()
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

                try await self.waitForStableDOMLength()
                let html: String = try await self.renderedHTML()
                self.finish(.success(html))
            } catch {
                self.finish(.failure(error))
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.targetFrame?.isMainFrame == true,
              let navigationURL: URL = navigationAction.request.url,
              let upgradedURL: URL = self.httpsURLIfNeeded(from: navigationURL) else {
            decisionHandler(.allow)
            return
        }

        self.isLoadingHTTPSUpgrade = true
        decisionHandler(.cancel)
        Task { @MainActor in
            webView.load(self.urlRequest(for: upgradedURL, includeBody: false))
        }
    }

    private func startEarlySnapshotPollingIfNeeded() {
        guard self.request?.autoScroll != true else {
            return
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: Timing.earlySnapshotInitialDelayNanoseconds)

            for _ in 0..<Timing.earlySnapshotAttempts {
                guard self.hasCompleted == false else {
                    return
                }

                if let html: String = try? await self.earlyRenderedHTMLIfReady() {
                    self.finish(.success(html))
                    return
                }

                try? await Task.sleep(nanoseconds: Timing.earlySnapshotIntervalNanoseconds)
            }
        }
    }

    private func startTimeout() {
        let timeoutNanoseconds: UInt64 = self.timeoutNanoseconds
        let timeoutSeconds: Double = self.timeoutSeconds
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            self.finish(
                .failure(
                    WKWebViewHTMLLoaderError.timedOut(
                        url: self.url,
                        seconds: timeoutSeconds
                    )
                )
            )
        }
    }

    private var timeoutNanoseconds: UInt64 {
        return self.request?.autoScroll == true
            ? Timing.autoScrollTimeoutNanoseconds
            : Timing.defaultTimeoutNanoseconds
    }

    private var timeoutSeconds: Double {
        return self.request?.autoScroll == true
            ? Timing.autoScrollTimeoutSeconds
            : Timing.defaultTimeoutSeconds
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

    /// 中文注释：WebView 使用同一份 RequestConfig header/body 语义，避免 HTTP 与 WebView 路径请求差异过大。
    private func urlRequest(for url: URL, includeBody: Bool) -> URLRequest {
        var urlRequest: URLRequest = URLRequest(url: url)
        urlRequest.httpMethod = self.request?.method?.rawValue ?? "GET"

        let headers: [String: String] = BrowserRequestHeaders.applyingOverrides(
            self.request?.headers,
            to: BrowserRequestHeaders.Chrome.defaultHeaders(for: url)
        )
        headers.forEach { key, value in
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        let cookieHeaders: [String: String] = CookieHeaderResolver.headersByApplyingPageCookies(
            to: urlRequest.allHTTPHeaderFields ?? [:],
            url: url,
            request: self.request
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

    private func waitForStableDOMLength() async throws {
        var previousLength: Int?

        for _ in 0..<Timing.domStableChecks {
            let currentLength: Int = try await self.renderedHTMLLength()
            if let previousLength: Int,
               abs(currentLength - previousLength) <= Timing.stableLengthDelta {
                return
            }

            previousLength = currentLength
            try await Task.sleep(nanoseconds: Timing.domStableDelayNanoseconds)
        }
    }

    private func renderedHTMLLength() async throws -> Int {
        let result: Any? = try await self.webView.evaluateJavaScript(
            "document.documentElement.outerHTML.length"
        )

        if let length: Int = result as? Int {
            return length
        }

        if let length: Double = result as? Double {
            return Int(length)
        }

        throw WKWebViewHTMLLoaderError.unexpectedJavaScriptResult(url: self.url)
    }

    private func earlyRenderedHTMLIfReady() async throws -> String? {
        let result: Any? = try await self.webView.evaluateJavaScript(
            """
            (() => {
              const root = document.documentElement;
              const body = document.body;
              const html = root ? root.outerHTML : "";
              const textLength = body ? (body.innerText || "").trim().length : 0;
              return {
                readyState: document.readyState || "",
                html: html,
                textLength: textLength
              };
            })();
            """
        )

        guard let state: [String: Any] = result as? [String: Any],
              let html: String = state["html"] as? String,
              let readyState: String = state["readyState"] as? String else {
            throw WKWebViewHTMLLoaderError.unexpectedJavaScriptResult(url: self.url)
        }

        guard readyState != "loading",
              html.count >= Timing.earlySnapshotMinimumHTMLLength,
              self.intValue(state["textLength"]) > 0 else {
            return nil
        }

        return html
    }

    /// 中文注释：读取 documentElement.outerHTML，确保解析器拿到的是 JS 执行后的整页 DOM。
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

    private func intValue(_ value: Any?) -> Int {
        if let int: Int = value as? Int {
            return int
        }

        if let double: Double = value as? Double {
            return Int(double)
        }

        return 0
    }

    private func finish(_ result: Result<String, Error>) {
        guard self.hasCompleted == false else {
            return
        }

        self.hasCompleted = true
        self.webView.stopLoading()
        self.webView.navigationDelegate = nil

        switch result {
        case .success(let html):
            self.continuation?.resume(returning: html)
        case .failure(let error):
            self.continuation?.resume(throwing: error)
        }

        self.continuation = nil
    }
}
