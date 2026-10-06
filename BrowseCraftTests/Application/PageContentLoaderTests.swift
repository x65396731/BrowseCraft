import Foundation
import Testing
@testable import BrowseCraft
import BrowseCraftCore
import BrowseCraftDomain

// 中文注释：页面内容加载器测试，确认 P1-4.3 的 HTTP/WebView 分流不会改变默认抓取路径。
struct PageContentLoaderTests {
    @Test func defaultLoaderUsesHTTPWhenWebViewIsNotRequired() async throws {
        let httpClient: RecordingPageHTTPClient = RecordingPageHTTPClient(html: "http-html")
        let renderedPageLoader: RecordingRenderedPageContentLoader = RecordingRenderedPageContentLoader(html: "webview-html")
        let loader: DefaultPageLoader = DefaultPageLoader(
            httpContentLoader: httpClient,
            httpDataLoader: httpClient,
            renderedPageContentLoader: renderedPageLoader,
            // 中文注释：注入了 rendered loader，策略不参与本用例；仍显式声明，避免出现隐藏默认值。
            domStabilityPolicy: .baseline
        )

        let html: String = try await loader.loadContent(
            PageLoadRequest(
                url: try #require(URL(string: "https://example.test/list")),
                requestConfig: nil,
                sourceContext: nil
            )
        ).content

        // 中文注释：未声明 needsWebView 时必须继续走 HTTP，保护既存站点的默认行为。
        #expect(html == "http-html")
        #expect(httpClient.requests.count == 1)
        #expect(renderedPageLoader.requests.isEmpty)
    }

    @Test func defaultLoaderUsesWebViewWhenRuleRequiresRenderedDOM() async throws {
        let httpClient: RecordingPageHTTPClient = RecordingPageHTTPClient(html: "http-html")
        let renderedPageLoader: RecordingRenderedPageContentLoader = RecordingRenderedPageContentLoader(html: "webview-html")
        let loader: DefaultPageLoader = DefaultPageLoader(
            httpContentLoader: httpClient,
            httpDataLoader: httpClient,
            renderedPageContentLoader: renderedPageLoader,
            // 中文注释：注入了 rendered loader，策略不参与本用例；仍显式声明，避免出现隐藏默认值。
            domStabilityPolicy: .baseline
        )
        let request: RequestConfig = RequestConfig(
            scope: .page,
            mergePolicy: .mergeHeaders,
            method: .get,
            headers: ["X-WebView-Test": "1"],
            body: nil,
            cookiePolicy: nil,
            cookiePriority: nil,
            cookieScope: nil,
            charset: nil,
            needsWebView: true,
            autoScroll: true,
            imageHeaders: nil,
            imageRequest: nil
        )

        let html: String = try await loader.loadContent(
            PageLoadRequest(
                url: try #require(URL(string: "https://example.test/js-page")),
                requestConfig: request,
                sourceContext: nil
            )
        ).content

        // 中文注释：声明 needsWebView 时应绕过 HTTP，交给 WebView 渲染后再返回 HTML。
        #expect(html == "webview-html")
        #expect(httpClient.requests.isEmpty)
        #expect(renderedPageLoader.requests.first?.requestConfig?.needsWebView == true)
        #expect(renderedPageLoader.requests.first?.requestConfig?.autoScroll == true)
    }

    @Test func defaultLoaderFallsBackToWebViewWhenHTTPPathHitsAntiBot() async throws {
        // 中文注释：`BCA-RUNTIME-005`——规则没声明 needsWebView，但手机出口的直接请求收到挑战页
        // （toonily 章节页 403 Cloudflare）：同一请求改走 WebView 再取一次。
        let httpClient: RecordingPageHTTPClient = RecordingPageHTTPClient(html: "http-html", throwAntiBot: true)
        let renderedPageLoader: RecordingRenderedPageContentLoader = RecordingRenderedPageContentLoader(html: "webview-html")
        let loader: DefaultPageLoader = DefaultPageLoader(
            httpContentLoader: httpClient,
            httpDataLoader: httpClient,
            renderedPageContentLoader: renderedPageLoader,
            domStabilityPolicy: .baseline
        )
        let url: URL = try #require(URL(string: "https://example.test/serie/x/chapter-1/"))

        let html: String = try await loader.loadContent(
            PageLoadRequest(url: url, requestConfig: nil, sourceContext: nil)
        ).content

        #expect(html == "webview-html")
        #expect(httpClient.requests.count == 1)
        #expect(renderedPageLoader.requests.count == 1)
        #expect(renderedPageLoader.requests.first?.url == url)
    }

    @Test func defaultLoaderDoesNotFallBackOnOtherHTTPErrors() async throws {
        // 中文注释：只有挑战页回退；网络等其它错误照旧抛出，不把 WebView 变成万能兜底。
        let httpClient: RecordingPageHTTPClient = RecordingPageHTTPClient(html: "http-html", throwNetwork: true)
        let renderedPageLoader: RecordingRenderedPageContentLoader = RecordingRenderedPageContentLoader(html: "webview-html")
        let loader: DefaultPageLoader = DefaultPageLoader(
            httpContentLoader: httpClient,
            httpDataLoader: httpClient,
            renderedPageContentLoader: renderedPageLoader,
            domStabilityPolicy: .baseline
        )

        await #expect(throws: RuleExecutionError.self) {
            _ = try await loader.loadContent(
                PageLoadRequest(
                    url: try #require(URL(string: "https://example.test/list")),
                    requestConfig: nil,
                    sourceContext: nil
                )
            )
        }
        #expect(renderedPageLoader.requests.isEmpty)
    }
}

private final class RecordingPageHTTPClient: PageContentLoader, PageDataLoader, @unchecked Sendable {
    private let html: String
    private let throwAntiBot: Bool
    private let throwNetwork: Bool
    private(set) var requests: [PageLoadRequest] = []

    init(html: String, throwAntiBot: Bool = false, throwNetwork: Bool = false) {
        self.html = html
        self.throwAntiBot = throwAntiBot
        self.throwNetwork = throwNetwork
    }

    func loadContent(_ request: PageLoadRequest) async throws -> PageContentResponse {
        self.requests.append(request)
        if self.throwAntiBot {
            throw RuleExecutionError.antiBot(url: request.url.absoluteString)
        }
        if self.throwNetwork {
            throw RuleExecutionError.network(url: request.url.absoluteString, underlyingDescription: "offline")
        }
        return PageContentResponse(
            content: self.html,
            finalURL: request.url
        )
    }

    func loadData(_ request: PageLoadRequest) async throws -> PageDataResponse {
        self.requests.append(request)
        return PageDataResponse(data: Data(self.html.utf8), finalURL: request.url)
    }
}

private final class RecordingRenderedPageContentLoader: RenderedPageContentLoader, @unchecked Sendable {
    private let html: String
    private(set) var requests: [PageLoadRequest] = []

    init(html: String) {
        self.html = html
    }

    @MainActor
    func loadRenderedContent(_ request: PageLoadRequest) async throws -> PageContentResponse {
        self.requests.append(request)
        return PageContentResponse(
            content: self.html,
            finalURL: request.url
        )
    }
}
