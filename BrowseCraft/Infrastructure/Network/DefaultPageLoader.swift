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
        systemCookieHeaderProvider: any SystemCookieHeaderProviding = EmptySystemCookieHeaderProvider()
    ) {
        self.httpContentLoader = httpContentLoader
        self.httpDataLoader = httpDataLoader
        self.renderedPageContentLoader = renderedPageContentLoader ?? WKWebViewHTMLLoader(
            credentialProvider: credentialProvider,
            browserRequestHeaderProvider: browserRequestHeaderProvider,
            systemCookieHeaderProvider: systemCookieHeaderProvider
        )
    }

    func loadContent(_ request: PageLoadRequest) async throws -> PageContentResponse {
        guard request.requestConfig?.needsWebView == true else {
            return try await self.httpContentLoader.loadContent(request)
        }

        #if DEBUG
        print(
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
