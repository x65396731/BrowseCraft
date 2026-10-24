import BrowseCraftDomain
import BrowseCraftLog
import Foundation
import Testing
@testable import BrowseCraft

struct AlamofireHTTPClientTests {
    @Test func safeURLDropsCredentialsQueryAndFragment() throws {
        let url: URL = try #require(
            URL(string: "https://user:password@example.test/feed?token=secret#fragment")
        )

        #expect(AppLog.safeURL(url) == "https://example.test/feed")
    }

    @Test func debugMessageRedactsCommonSecrets() {
        let message: String = AppLog.sanitizedDebugMessage(
            "authorization=Bearer-secret cookie=session-secret token=abc"
        )

        #expect(message.contains("Bearer-secret") == false)
        #expect(message.contains("session-secret") == false)
        #expect(message.contains("token=<redacted>"))
    }

    @Test func debugMessageRedactsURLQuery() {
        let message: String = AppLog.sanitizedDebugMessage(
            "request=https://example.test/feed?token=secret"
        )

        #expect(message == "request=https://example.test/feed?<redacted>")
    }

    // 中文注释：`BCA-RUNTIME-007`——与预检同口径：200..<400 照旧解析，≥ 400 先认挑战页、其余报 httpStatus。
    @Test func contentFailureRejectsNonChallengeErrorStatus() throws {
        let url: URL = try #require(URL(string: "https://example.test/vodtype/1.html"))
        let forbidden: RuleExecutionError? = AlamofireHTTPClient.contentFailure(
            statusCode: 403,
            html: "<html><body><h1>403 Forbidden</h1></body></html>",
            url: url
        )

        #expect(forbidden == .httpStatus(url: url.absoluteString, statusCode: 403))
        #expect(
            AlamofireHTTPClient.contentFailure(statusCode: 503, html: "<html>down</html>", url: url)
                == .httpStatus(url: url.absoluteString, statusCode: 503)
        )
    }

    @Test func contentFailureKeepsChallengePageAsAntiBotForWebViewFallback() throws {
        let url: URL = try #require(URL(string: "https://example.test/chapter/1"))
        let challenge: String = "<html><head><title>Just a moment...</title></head><body></body></html>"

        // 中文注释：Cloudflare 挑战页常以 403 回应；必须仍是 antiBot，才能走 BCA-RUNTIME-005 的 WebView 回退。
        #expect(
            AlamofireHTTPClient.contentFailure(statusCode: 403, html: challenge, url: url)
                == .antiBot(url: url.absoluteString)
        )
    }

    @Test func contentFailureLetsSuccessAndRedirectStatusThrough() throws {
        let url: URL = try #require(URL(string: "https://example.test/list"))
        let page: String = "<html><body><ul><li>item</li></ul></body></html>"

        #expect(AlamofireHTTPClient.contentFailure(statusCode: 200, html: page, url: url) == nil)
        #expect(AlamofireHTTPClient.contentFailure(statusCode: 304, html: page, url: url) == nil)
        #expect(AlamofireHTTPClient.contentFailure(statusCode: nil, html: page, url: url) == nil)
    }

    // 中文注释：调用方取消要原样抛 `CancellationError`，不能包成 `RuleExecutionError.network`——
    // 否则库页把「Request explicitly cancelled.」当网络失败显示（2026-10-24 问题报告 R-UHEE-SAMK）。
    @Test func cancelledContentLoadThrowsCancellationNotNetworkFailure() async throws {
        let client: AlamofireHTTPClient = AlamofireHTTPClient()
        let url: URL = try #require(URL(string: "https://example.test/list"))
        let task: Task<PageContentResponse, any Error> = Task {
            try await client.loadContent(PageLoadRequest(url: url, requestConfig: nil, sourceContext: nil))
        }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }

    @Test func cancelledDataLoadThrowsCancellationNotNetworkFailure() async throws {
        let client: AlamofireHTTPClient = AlamofireHTTPClient()
        let url: URL = try #require(URL(string: "https://example.test/feed.json"))
        let task: Task<PageDataResponse, any Error> = Task {
            try await client.loadData(PageLoadRequest(url: url, requestConfig: nil, sourceContext: nil))
        }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }
}
