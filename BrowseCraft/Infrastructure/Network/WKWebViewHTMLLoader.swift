import Foundation
import WebKit

// 中文注释：WKWebViewHTMLLoader.swift 负责把需要 JS 渲染的页面加载成最终 HTML，再交给原有解析器。

/// 中文注释：WebView 渲染失败时提供明确错误，方便区分 URL、导航和 DOM 读取问题。
enum WKWebViewHTMLLoaderError: LocalizedError {
    case emptyHTML(url: URL)
    case unexpectedJavaScriptResult(url: URL)

    var errorDescription: String? {
        switch self {
        case .emptyHTML(let url):
            return "WebView rendered empty HTML: \(url.absoluteString)"
        case .unexpectedJavaScriptResult(let url):
            return "WebView returned unexpected JavaScript result: \(url.absoluteString)"
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
    private let url: URL
    private let request: RequestConfig?
    private let webView: WKWebView
    private var continuation: CheckedContinuation<String, Error>?
    private var hasCompleted: Bool = false

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
                self.webView.load(self.urlRequest())
            }
        } onCancel: {
            Task { @MainActor in
                self.finish(.failure(CancellationError()))
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            do {
                if self.request?.autoScroll == true {
                    try await self.scrollToBottom()
                }

                let html: String = try await self.renderedHTML()
                self.finish(.success(html))
            } catch {
                self.finish(.failure(error))
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.finish(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.finish(.failure(error))
    }

    /// 中文注释：WebView 使用同一份 RequestConfig header/body 语义，避免 HTTP 与 WebView 路径请求差异过大。
    private func urlRequest() -> URLRequest {
        var urlRequest: URLRequest = URLRequest(url: self.url)
        urlRequest.httpMethod = self.request?.method?.rawValue ?? "GET"

        self.defaultHeaders().forEach { key, value in
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        self.request?.headers?.forEach { key, value in
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        let cookieHeaders: [String: String] = CookieHeaderResolver.headersByApplyingPageCookies(
            to: urlRequest.allHTTPHeaderFields ?? [:],
            url: self.url,
            request: self.request
        )
        cookieHeaders.forEach { key, value in
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        if let body: RequestBody = self.request?.body {
            urlRequest.httpBody = Data(body.value.utf8)
            if let contentType: String = body.contentType {
                urlRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
            }
        }

        return urlRequest
    }

    /// 中文注释：默认 header 模拟移动端浏览器访问，保持和 AlamofireHTTPClient 的旧抓取行为一致。
    private func defaultHeaders() -> [String: String] {
        return [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh-Hans;q=0.9,zh;q=0.8,en;q=0.5",
            "Referer": "\(self.url.scheme ?? "https")://\(self.url.host ?? "")/"
        ]
    }

    /// 中文注释：部分懒加载站点需要滚动后才把图片或列表节点写入 DOM，当前先提供一次性滚到底能力。
    private func scrollToBottom() async throws {
        _ = try await self.webView.evaluateJavaScript(
            "window.scrollTo(0, document.body.scrollHeight);"
        )
        try await Task.sleep(nanoseconds: 300_000_000)
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
