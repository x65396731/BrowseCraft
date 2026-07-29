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
}
