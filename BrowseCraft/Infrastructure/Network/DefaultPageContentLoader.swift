import Foundation

// 中文注释：DefaultPageContentLoader.swift 是页面内容加载的生产分流器，统一判断 HTTP 与 WebView 路径。

/// 中文注释：默认页面加载器；没有 needsWebView 时保持 Alamofire 抓取，只有规则显式要求时才走 WebView。
final class DefaultPageContentLoader: ContextualPageContentResponseLoader, ContextualPageDataLoader {
    private let httpClient: HTTPClient
    private let renderedPageContentLoader: RenderedPageContentLoader

    init(
        httpClient: HTTPClient,
        renderedPageContentLoader: RenderedPageContentLoader? = nil,
        credentialProvider: any SourceCredentialProviding = EmptySourceCredentialProvider()
    ) {
        self.httpClient = httpClient
        self.renderedPageContentLoader = renderedPageContentLoader ?? WKWebViewHTMLLoader(
            credentialProvider: credentialProvider
        )
    }

    /// 中文注释：P1-4.3 的核心分流点；WebView 只作为页面获取能力，不改变原生列表和阅读 UI。
    func getString(from url: URL, request: RequestConfig?) async throws -> String {
        return try await self.getString(from: url, request: request, context: nil)
    }

    func getString(from url: URL, request: RequestConfig?, context: SourceRequestContext?) async throws -> String {
        return try await self.getStringResponse(from: url, request: request, context: context).content
    }

    func getStringResponse(
        from url: URL,
        request: RequestConfig?,
        context: SourceRequestContext?
    ) async throws -> PageContentResponse {
        guard request?.needsWebView == true else {
            if let responseLoader: any ContextualPageContentResponseLoader = self.httpClient as? any ContextualPageContentResponseLoader {
                return try await responseLoader.getStringResponse(from: url, request: request, context: context)
            }
            return PageContentResponse(
                content: try await self.httpClient.getString(from: url, request: request),
                finalURL: url
            )
        }

        #if DEBUG
        print(
            "[BrowseCraftWebView] render html " +
            "url=\(url.absoluteString) " +
            "scope=\(request?.scope?.rawValue ?? "default") " +
            "autoScroll=\(request?.autoScroll?.description ?? "nil")"
        )
        #endif

        return PageContentResponse(
            content: try await self.renderedPageContentLoader.getRenderedString(
                from: url,
                request: request,
                context: context
            ),
            finalURL: url
        )
    }

    func getData(from url: URL, request: RequestConfig?) async throws -> Data {
        return try await self.getData(from: url, request: request, context: nil)
    }

    func getData(from url: URL, request: RequestConfig?, context: SourceRequestContext?) async throws -> Data {
        if let contextualHTTPClient: ContextualPageDataLoader = self.httpClient as? ContextualPageDataLoader {
            return try await contextualHTTPClient.getData(from: url, request: request, context: context)
        }
        return try await self.httpClient.getData(from: url, request: request)
    }
}
