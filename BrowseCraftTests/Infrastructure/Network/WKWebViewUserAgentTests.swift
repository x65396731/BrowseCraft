import BrowseCraftCore
import BrowseCraftDomain
import XCTest
@testable import BrowseCraft

/// `BC-ACQ-044` 的请求头轴在 WKWebView 路径上要靠 `customUserAgent` 才成立。
///
/// 中文注释：**WebKit 会用自己的 UA 覆盖 `URLRequest` 上的 `User-Agent`**，所以加载器里
/// `setValue` 的那一行对渲染路径无效。设计书 23.6 当初写下的「App 两条路发出的都是规则里
/// 那个串」对 URLSession 成立、对这条路不成立——当时没有实测渲染路径。
///
/// 2026-09-19 真机逮到：`BC-ACQ-059` 把采集面换成桌面 UA 之后，引擎在 178 的阅读页学到
/// 桌面模板选择器 `div.comicpage img`（同一章节页桌面 76 KB / 35 张图），WKWebView 仍发
/// iOS Safari UA、拿到移动模板（15.7 KB，容器 `div#cp_img`），于是
/// `dom-stability matched=40` 却 `pageCount=0`、`selectorEmpty`。
///
/// 本用例走**真实的** WKWebViewHTMLLoader，让页面自己把 `navigator.userAgent` 写进 DOM，
/// 因此验的是「UA 真的生效了」，不是「我们调用了某个 API」。
/// 反向植入（去掉 `applyUserAgent`）必须使它失败。
@MainActor
final class WKWebViewUserAgentTests: XCTestCase {
    private static let echoUserAgent: String = """
    <html><body><div id="ua"></div>
    <script>document.getElementById("ua").textContent = navigator.userAgent;</script>
    </body></html>
    """

    func testRuleDeclaredUserAgentReachesTheRenderedPage() async throws {
        let declared: String = "BrowseCraftTest/1.0 (rule-declared-agent)"
        let html: String = try await self.load(userAgent: declared)
        XCTAssertTrue(
            html.contains(declared),
            "规则声明的 UA 没有到达渲染页面；WKWebView 需要 customUserAgent，setValue 不生效"
        )
    }

    func testWithoutADeclaredUserAgentTheWebViewKeepsItsOwn() async throws {
        let html: String = try await self.load(userAgent: nil)
        // 不声明时保持 WKWebView 自己的 UA——与本改动之前逐字相同。
        XCTAssertFalse(html.contains("rule-declared-agent"), html)
        XCTAssertTrue(html.contains("Mozilla/"), "页面应当回显出 WebView 自己的 UA")
    }

    private func load(userAgent: String?) async throws -> String {
        let encoded: String = try XCTUnwrap(
            Self.echoUserAgent.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
        )
        let url: URL = try XCTUnwrap(URL(string: "data:text/html;charset=utf-8," + encoded))
        var config = RequestConfig()
        config.needsWebView = true
        if let userAgent: String {
            config.headers = ["User-Agent": userAgent]
        }
        let loader: WKWebViewHTMLLoader = WKWebViewHTMLLoader(domStabilityPolicy: .baseline)
        let response: PageContentResponse = try await loader.loadRenderedContent(
            PageLoadRequest(
                url: url,
                requestConfig: config,
                sourceContext: nil,
                readinessSelector: "#ua"
            )
        )
        return response.content
    }
}
