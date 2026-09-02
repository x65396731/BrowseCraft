import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft

// 中文注释：BC-EVIDENCE-079.4——探针与原生播放器共用的请求头组合。
struct VideoPlaybackRequestHeadersTests {
    private struct FixtureHeaderProvider: BrowserRequestHeaderProviding {
        let userAgent: String = "Fixture/Browser"

        func defaultHeaders(for url: URL, referer: URL?, includeOrigin: Bool) -> [String: String] {
            var headers: [String: String] = ["User-Agent": self.userAgent, "Accept": "*/*"]
            if let referer: URL { headers["Referer"] = referer.absoluteString }
            return headers
        }
    }

    @Test func browserDefaultsAreAppliedEvenWithoutRequestConfig() throws {
        let headers = VideoPlaybackRequestHeaders.compose(
            mediaURL: try #require(URL(string: "https://cdn.example.invalid/a.mp4")),
            requestConfig: nil,
            browserRequestHeaderProvider: FixtureHeaderProvider()
        )
        #expect(headers["User-Agent"] == "Fixture/Browser")
        #expect(headers["Accept"] == "*/*")
    }

    @Test func catalogOverridesAndRefererOriginAreAdded() throws {
        let referer: URL = try #require(URL(string: "https://site.example.invalid/watch/1"))
        let headers = VideoPlaybackRequestHeaders.compose(
            mediaURL: try #require(URL(string: "https://cdn.example.invalid/a.mp4")),
            requestConfig: SourcePlaybackRequestConfig(
                headers: ["X-Token": "abc"],
                referer: referer,
                userAgent: nil
            ),
            browserRequestHeaderProvider: FixtureHeaderProvider()
        )
        #expect(headers["X-Token"] == "abc")
        #expect(headers["Referer"] == referer.absoluteString)
        #expect(headers["User-Agent"] == "Fixture/Browser")
        #expect(headers["Origin"] == "https://site.example.invalid")
    }

    // 中文注释：BC-EVIDENCE-079.6——octet-stream 允许进入 ftyp 校验；其它类型仍 mismatch。
    @Test func mp4ContentTypeAllowsOctetStreamButNotHTML() {
        #expect(VideoRuntimeAuditMediaProbe.contentTypeAllowsMP4("video/mp4"))
        #expect(VideoRuntimeAuditMediaProbe.contentTypeAllowsMP4("application/octet-stream; charset=binary"))
        #expect(VideoRuntimeAuditMediaProbe.contentTypeAllowsMP4("text/html; charset=utf-8") == false)
        var mp4: Data = Data([0, 0, 0, 24]); mp4.append(Data("ftypisom".utf8)); mp4.append(Data(repeating: 0, count: 8))
        #expect(VideoRuntimeAuditMediaProbe.hasFtypSignature(mp4))
        #expect(VideoRuntimeAuditMediaProbe.hasFtypSignature(Data("<html>not-a-video</html>".utf8)) == false)
    }

    @Test func catalogUserAgentWinsOverBrowserDefault() throws {
        let headers = VideoPlaybackRequestHeaders.compose(
            mediaURL: try #require(URL(string: "https://cdn.example.invalid/a.m3u8")),
            requestConfig: SourcePlaybackRequestConfig(
                headers: ["User-Agent": "Catalog/UA"],
                referer: nil,
                userAgent: nil
            ),
            browserRequestHeaderProvider: FixtureHeaderProvider()
        )
        #expect(headers["User-Agent"] == "Catalog/UA")
    }
}
