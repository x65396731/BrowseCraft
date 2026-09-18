import BrowseCraftCore
import BrowseCraftDomain
import XCTest
@testable import BrowseCraft

// 中文注释：走**真实的** WKWebViewHTMLLoader（didFinish → 固定 500ms → DOM 稳定判定 → 取整页 HTML），
// 只把页面换成 data: URL，验证 PageLoadRequest.readinessSelector 确实穿过加载器到达判定，并让加载提前返回。
// 这是「规则 ready → 请求字段 → 加载器 → 判定」链路里，唯一没被其它用例覆盖的一段（加载器内的透传）。
@MainActor
final class WKWebViewHTMLLoaderReadinessTests: XCTestCase {
    private static let staticList: String = """
    <html><body><ul id="list"><li class="item">a</li><li class="item">b</li><li class="item">c</li></ul></body></html>
    """

    private static let lateList: String = """
    <html><body><ul id="list"></ul>
    <script>setTimeout(() => { document.getElementById("list").innerHTML = '<li class="item">a</li><li class="item">b</li><li class="item">c</li>'; }, 800);</script>
    </body></html>
    """

    func testStaticListReturnsEarlyWhenTheRequestDeclaresAReadinessSelector() async throws {
        let baseline: (Duration, String) = try await self.load(Self.staticList, readinessSelector: nil)
        let gated: (Duration, String) = try await self.load(Self.staticList, readinessSelector: ".item")
        print("[loader readiness] staticList baseline=\(baseline.0.milliseconds)ms selector=\(gated.0.milliseconds)ms")

        XCTAssertEqual(Self.count(of: "class=\"item\"", in: gated.1), 3)
        // 基线 = 500ms 固定延迟 + 约 1500ms 下限；声明选择器后应明显更早。
        XCTAssertGreaterThanOrEqual(baseline.0.milliseconds, 1_800)
        XCTAssertLessThan(gated.0.milliseconds, baseline.0.milliseconds - 800)
    }

    func testLateListStillContainsTheItemsWhenReturningEarly() async throws {
        let gated: (Duration, String) = try await self.load(Self.lateList, readinessSelector: ".item")
        print("[loader readiness] lateList selector=\(gated.0.milliseconds)ms")

        XCTAssertEqual(Self.count(of: "class=\"item\"", in: gated.1), 3, "提前返回时 3 个条目必须已在 HTML 里")
        XCTAssertGreaterThanOrEqual(gated.0.milliseconds, 800 + 500)
    }

    private func load(_ html: String, readinessSelector: String?) async throws -> (Duration, String) {
        let encoded: String = try XCTUnwrap(html.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
        let url: URL = try XCTUnwrap(URL(string: "data:text/html;charset=utf-8," + encoded))
        let loader: WKWebViewHTMLLoader = WKWebViewHTMLLoader(domStabilityPolicy: .baseline)
        let start: ContinuousClock.Instant = ContinuousClock.now
        let response: PageContentResponse = try await loader.loadRenderedContent(
            PageLoadRequest(
                url: url,
                requestConfig: RequestConfig(needsWebView: true),
                sourceContext: nil,
                readinessSelector: readinessSelector
            )
        )
        return (ContinuousClock.now - start, response.content)
    }

    /// 中文注释：只数 `<ul id="list">…</ul>` 里渲染出来的条目——lateList 的 `<script>` 源码里也含同样的字面量，
    /// 数整页会把脚本文本算进去（首轮实测得 6：3 个脚本字面量 + 3 个真渲染出的）。
    private static func count(of needle: String, in html: String) -> Int {
        guard let start: Range<String.Index> = html.range(of: "<ul id=\"list\">"),
              let end: Range<String.Index> = html.range(of: "</ul>", range: start.upperBound..<html.endIndex) else {
            return 0
        }
        return String(html[start.upperBound..<end.lowerBound]).components(separatedBy: needle).count - 1
    }
}
