import Foundation
import Testing
@testable import BrowseCraft

// 中文注释：页面内容加载器测试，确认 P1-4.3 的 HTTP/WebView 分流不会改变默认抓取路径。
struct PageContentLoaderTests {
    @Test func defaultLoaderUsesHTTPWhenWebViewIsNotRequired() async throws {
        let httpClient: RecordingPageHTTPClient = RecordingPageHTTPClient(html: "http-html")
        let renderedPageLoader: RecordingRenderedPageContentLoader = RecordingRenderedPageContentLoader(html: "webview-html")
        let loader: DefaultPageLoader = DefaultPageLoader(
            httpContentLoader: httpClient,
            httpDataLoader: httpClient,
            renderedPageContentLoader: renderedPageLoader
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
            renderedPageContentLoader: renderedPageLoader
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
}

private final class RecordingPageHTTPClient: PageContentLoader, PageDataLoader {
    private let html: String
    private(set) var requests: [PageLoadRequest] = []

    init(html: String) {
        self.html = html
    }

    func loadContent(_ request: PageLoadRequest) async throws -> PageContentResponse {
        self.requests.append(request)
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

private final class RecordingRenderedPageContentLoader: RenderedPageContentLoader {
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
