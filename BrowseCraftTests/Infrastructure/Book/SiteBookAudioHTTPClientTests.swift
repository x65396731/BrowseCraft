import Foundation
import ReadiumShared
import Testing
@testable import BrowseCraft

// 中文注释：音频请求 http → https 升级；https 与非 http 原样。
struct SiteBookAudioHTTPClientTests {
    @Test func httpRequestsAreUpgradedToHTTPS() throws {
        let http: HTTPURL = try #require(HTTPURL(url: URL(string: "http://www.archive.org/download/a/b_64kb.mp3?x=1")!))
        let upgraded: HTTPRequest = SiteBookAudioHTTPClient.upgradedToHTTPS(HTTPRequest(url: http))
        #expect(upgraded.url.url.absoluteString == "https://www.archive.org/download/a/b_64kb.mp3?x=1")

        let https: HTTPURL = try #require(HTTPURL(url: URL(string: "https://archive.org/download/a/b.mp3")!))
        #expect(SiteBookAudioHTTPClient.upgradedToHTTPS(HTTPRequest(url: https)).url == https)
    }

    @Test func clientKeepsItsDelegateAlive() {
        let client: SiteBookAudioHTTPClient = SiteBookAudioHTTPClient()
        #expect(client.client.delegate === client)
    }
}
