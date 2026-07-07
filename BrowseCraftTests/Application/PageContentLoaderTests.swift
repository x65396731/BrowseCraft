import Foundation
import Testing
@testable import BrowseCraft

// 中文注释：页面内容加载器测试，确认 P1-4.3 的 HTTP/WebView 分流不会改变默认抓取路径。
struct PageContentLoaderTests {
    @Test func defaultLoaderUsesHTTPWhenWebViewIsNotRequired() async throws {
        let httpClient: RecordingPageHTTPClient = RecordingPageHTTPClient(html: "http-html")
        let renderedPageLoader: RecordingRenderedPageContentLoader = RecordingRenderedPageContentLoader(html: "webview-html")
        let loader: DefaultPageContentLoader = DefaultPageContentLoader(
            httpClient: httpClient,
            renderedPageContentLoader: renderedPageLoader
        )

        let html: String = try await loader.getString(
            from: try #require(URL(string: "https://example.test/list")),
            request: nil
        )

        // 中文注释：未声明 needsWebView 时必须继续走 HTTP，保护既存站点的默认行为。
        #expect(html == "http-html")
        #expect(httpClient.requests.count == 1)
        #expect(renderedPageLoader.requests.isEmpty)
    }

    @Test func defaultLoaderUsesWebViewWhenRuleRequiresRenderedDOM() async throws {
        let httpClient: RecordingPageHTTPClient = RecordingPageHTTPClient(html: "http-html")
        let renderedPageLoader: RecordingRenderedPageContentLoader = RecordingRenderedPageContentLoader(html: "webview-html")
        let loader: DefaultPageContentLoader = DefaultPageContentLoader(
            httpClient: httpClient,
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

        let html: String = try await loader.getString(
            from: try #require(URL(string: "https://example.test/js-page")),
            request: request
        )

        // 中文注释：声明 needsWebView 时应绕过 HTTP，交给 WebView 渲染后再返回 HTML。
        #expect(html == "webview-html")
        #expect(httpClient.requests.isEmpty)
        #expect(renderedPageLoader.requests.first?.request?.needsWebView == true)
        #expect(renderedPageLoader.requests.first?.request?.autoScroll == true)
    }
}

private final class RecordingPageHTTPClient: HTTPClient {
    struct RecordedRequest: Hashable {
        var url: URL
        var request: RequestConfig?
    }

    private let html: String
    private(set) var requests: [RecordedRequest] = []

    init(html: String) {
        self.html = html
    }

    func getString(from url: URL, request: RequestConfig?) async throws -> String {
        self.requests.append(
            RecordedRequest(
                url: url,
                request: request
            )
        )

        return self.html
    }

    func getData(from url: URL, request: RequestConfig?) async throws -> Data {
        let html: String = try await self.getString(from: url, request: request)
        return Data(html.utf8)
    }
}

private final class RecordingRenderedPageContentLoader: RenderedPageContentLoader {
    struct RecordedRequest: Hashable {
        var url: URL
        var request: RequestConfig?
    }

    private let html: String
    private(set) var requests: [RecordedRequest] = []

    init(html: String) {
        self.html = html
    }

    @MainActor
    func getRenderedString(from url: URL, request: RequestConfig?) async throws -> String {
        self.requests.append(
            RecordedRequest(
                url: url,
                request: request
            )
        )

        return self.html
    }
}
