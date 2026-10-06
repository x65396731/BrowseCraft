import BrowseCraftDomain
import Foundation

// 中文注释：DefaultPageLoader 是页面加载的生产分流器，统一选择 HTTP 或 WebView 路径。

final class DefaultPageLoader: PageContentLoader, PageDataLoader {
    private let httpContentLoader: PageContentLoader
    private let httpDataLoader: PageDataLoader
    private let renderedPageContentLoader: RenderedPageContentLoader

    init(
        httpContentLoader: PageContentLoader,
        httpDataLoader: PageDataLoader,
        renderedPageContentLoader: RenderedPageContentLoader? = nil,
        credentialProvider: any SourceCredentialProviding = EmptySourceCredentialProvider(),
        browserRequestHeaderProvider: any BrowserRequestHeaderProviding = EmptyBrowserRequestHeaderProvider(),
        systemCookieHeaderProvider: any SystemCookieHeaderProviding = EmptySystemCookieHeaderProvider(),
        domStabilityPolicy: WKWebViewDOMStabilityPolicy
    ) {
        self.httpContentLoader = httpContentLoader
        self.httpDataLoader = httpDataLoader
        self.renderedPageContentLoader = renderedPageContentLoader ?? WKWebViewHTMLLoader(
            credentialProvider: credentialProvider,
            browserRequestHeaderProvider: browserRequestHeaderProvider,
            systemCookieHeaderProvider: systemCookieHeaderProvider,
            domStabilityPolicy: domStabilityPolicy
        )
    }

    func loadContent(_ request: PageLoadRequest) async throws -> PageContentResponse {
        guard request.requestConfig?.needsWebView == true else {
            do {
                return try await self.httpContentLoader.loadContent(request)
            } catch RuleExecutionError.antiBot {
                // 中文注释：`BCA-RUNTIME-005`——规则按服务器出口判「不需渲染」，手机出口却收到挑战页
                // （toonily 章节页 403 Cloudflare 挑战）；同一请求改走 WebView 再取一次，由
                // `BC-EVIDENCE-081` 的挑战页状态机等它过去。无反爬的站不会进到这里。
                #if DEBUG
                AppDebugLog.write(
                    "[BrowseCraftWebView] anti-bot on http path, retrying via webview " +
                    "url=\(request.url.absoluteString)"
                )
                #endif
                return try await self.renderedPageContentLoader.loadRenderedContent(request)
            }
        }

        #if DEBUG
        AppDebugLog.write(
            "[BrowseCraftWebView] render html " +
            "url=\(request.url.absoluteString) " +
            "scope=\(request.requestConfig?.scope?.rawValue ?? "default") " +
            "autoScroll=\(request.requestConfig?.autoScroll?.description ?? "nil")"
        )
        #endif

        return try await self.renderedPageContentLoader.loadRenderedContent(request)
    }

    func loadData(_ request: PageLoadRequest) async throws -> PageDataResponse {
        return try await self.httpDataLoader.loadData(request)
    }
}
