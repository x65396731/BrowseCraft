import Foundation

// 中文注释：DefaultPageContentLoader.swift 是页面内容加载的生产分流器，统一判断 HTTP 与 WebView 路径。

/// 中文注释：默认页面加载器；没有 needsWebView 时保持 Alamofire 抓取，只有规则显式要求时才走 WebView。
final class DefaultPageContentLoader: PageContentLoader {
    private let httpClient: HTTPClient
    private let webViewContentLoader: WebViewContentLoader

    init(
        httpClient: HTTPClient,
        webViewContentLoader: WebViewContentLoader = WKWebViewHTMLLoader()
    ) {
        self.httpClient = httpClient
        self.webViewContentLoader = webViewContentLoader
    }

    /// 中文注释：P1-4.3 的核心分流点；WebView 只作为页面获取能力，不改变原生列表和阅读 UI。
    func getString(from url: URL, request: RequestConfig?) async throws -> String {
        guard request?.needsWebView == true else {
            return try await self.httpClient.getString(from: url, request: request)
        }

        #if DEBUG
        print(
            "[BrowseCraftWebView] render html " +
            "url=\(url.absoluteString) " +
            "scope=\(request?.scope?.rawValue ?? "default") " +
            "autoScroll=\(request?.autoScroll?.description ?? "nil")"
        )
        #endif

        return try await self.webViewContentLoader.getRenderedString(
            from: url,
            request: request
        )
    }
}
