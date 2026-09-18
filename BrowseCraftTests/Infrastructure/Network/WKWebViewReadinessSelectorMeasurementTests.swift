import WebKit
import XCTest
@testable import BrowseCraft

// 中文注释：「就绪选择器」的固定输入测量。合成页面经 loadHTMLString 注入，不访问真实站点。
// 守住三条不变量：
// 1. 声明了选择器的页面，永远不比不声明更慢（选择器只是加速条件，历史判定逐字保留为兜底）。
// 2. 内容在 DOM 里出现之前不得返回（延迟写入的夹具在返回时正文必须已存在）。
// 3. 非法选择器等价于未声明，不报错、不更慢。
// 具体毫秒数打印出来供审阅；断言只用宽松界限，避免模拟器计时抖动造成误报。
@MainActor
final class WKWebViewReadinessSelectorMeasurementTests: XCTestCase {
    private enum Fixture {
        /// 中文注释：加载完即有 3 个条目的静态列表页。
        static let quietList: String = """
        <html><body><ul id="list">
          <li class="item">a</li><li class="item">b</li><li class="item">c</li>
        </ul></body></html>
        """

        /// 中文注释：800ms 后才把条目写进列表（服务端渲染后补内容）。
        static let lateList: String = """
        <html><body><ul id="list"></ul>
        <script>
          setTimeout(() => {
            document.getElementById("list").innerHTML =
              '<li class="item">a</li><li class="item">b</li><li class="item">c</li>' + "<p>" + "x".repeat(4000) + "</p>";
          }, 800);
        </script>
        </body></html>
        """

        /// 中文注释：选择器永远不命中（空列表页）。声明选择器不得比不声明更慢。
        static let emptyList: String = """
        <html><body><ul id="list"></ul><p>nothing here</p></body></html>
        """

        /// 中文注释：分批追加：每 250ms 追加一个条目，共 5 个后停止。数量稳定后才算就绪。
        static let lazyAppendList: String = """
        <html><body><ul id="list"></ul>
        <script>
          let added = 0;
          const timer = setInterval(() => {
            const node = document.createElement("li");
            node.className = "item";
            node.textContent = "item " + (added += 1) + " " + "y".repeat(300);
            document.getElementById("list").appendChild(node);
            if (added >= 5) { clearInterval(timer); }
          }, 250);
        </script>
        </body></html>
        """
    }

    func testQuietListReturnsAsSoonAsTheSelectorIsStable() async throws {
        let baseline: WKWebViewDOMStabilityWaiter.Outcome = try await self.measure(Fixture.quietList, selector: nil)
        let gated: WKWebViewDOMStabilityWaiter.Outcome = try await self.measure(Fixture.quietList, selector: ".item")
        Self.report("quietList", baseline: baseline, gated: gated)

        XCTAssertEqual(gated.reason, .selectorReady)
        XCTAssertEqual(gated.matchedCount, 3)
        XCTAssertGreaterThanOrEqual(baseline.waited.milliseconds, 1_400)
        XCTAssertLessThan(gated.waited.milliseconds, 1_000)
    }

    func testLateListNeverReturnsBeforeTheItemsExist() async throws {
        let baseline: WKWebViewDOMStabilityWaiter.Outcome = try await self.measure(Fixture.lateList, selector: nil)
        let (gated, webView): (WKWebViewDOMStabilityWaiter.Outcome, WKWebView) = try await self.measureKeepingWebView(Fixture.lateList, selector: ".item")
        let itemCount: Int = try await Self.count(of: ".item", in: webView)
        Self.report("lateList", baseline: baseline, gated: gated)

        XCTAssertEqual(gated.reason, .selectorReady)
        XCTAssertEqual(itemCount, 3, "返回时条目必须已经在 DOM 里")
        XCTAssertGreaterThanOrEqual(gated.waited.milliseconds, 800)
        XCTAssertLessThanOrEqual(gated.waited.milliseconds, baseline.waited.milliseconds + 400)
    }

    func testEmptyListIsNotSlowerWhenTheSelectorNeverMatches() async throws {
        let baseline: WKWebViewDOMStabilityWaiter.Outcome = try await self.measure(Fixture.emptyList, selector: nil)
        let gated: WKWebViewDOMStabilityWaiter.Outcome = try await self.measure(Fixture.emptyList, selector: ".item")
        Self.report("emptyList", baseline: baseline, gated: gated)

        XCTAssertEqual(gated.reason, .quiet, "不命中时退回历史判定")
        XCTAssertEqual(gated.matchedCount, 0)
        XCTAssertLessThanOrEqual(gated.waited.milliseconds, baseline.waited.milliseconds + 400)
    }

    func testLazyAppendWaitsForTheCountToSettle() async throws {
        let baseline: WKWebViewDOMStabilityWaiter.Outcome = try await self.measure(Fixture.lazyAppendList, selector: nil)
        let (gated, webView): (WKWebViewDOMStabilityWaiter.Outcome, WKWebView) = try await self.measureKeepingWebView(Fixture.lazyAppendList, selector: ".item")
        let itemCount: Int = try await Self.count(of: ".item", in: webView)
        Self.report("lazyAppendList", baseline: baseline, gated: gated)

        // 中文注释：离屏 WebView 会节流 setInterval，追加节奏不可预期；只守「返回时数量已稳定」与「不慢于基线」。
        XCTAssertGreaterThan(gated.matchedCount ?? 0, 0)
        XCTAssertEqual(gated.matchedCount, itemCount, "返回时报告的命中数必须等于当时 DOM 里的数量")
        XCTAssertLessThanOrEqual(gated.waited.milliseconds, baseline.waited.milliseconds + 400)
    }

    func testInvalidSelectorBehavesLikeNoSelector() async throws {
        let baseline: WKWebViewDOMStabilityWaiter.Outcome = try await self.measure(Fixture.quietList, selector: nil)
        let gated: WKWebViewDOMStabilityWaiter.Outcome = try await self.measure(Fixture.quietList, selector: "li[")
        Self.report("invalidSelector", baseline: baseline, gated: gated)

        XCTAssertEqual(gated.reason, .quiet)
        XCTAssertEqual(gated.matchedCount, -1, "非法选择器记为 -1，按未命中处理")
        XCTAssertLessThanOrEqual(gated.waited.milliseconds, baseline.waited.milliseconds + 400)
    }

    // MARK: - 测量夹具

    private func measure(_ html: String, selector: String?) async throws -> WKWebViewDOMStabilityWaiter.Outcome {
        return try await self.measureKeepingWebView(html, selector: selector).0
    }

    private func measureKeepingWebView(_ html: String, selector: String?) async throws -> (WKWebViewDOMStabilityWaiter.Outcome, WKWebView) {
        let webView: WKWebView = WKWebView(frame: .zero)
        let navigation: NavigationObserver = NavigationObserver()
        webView.navigationDelegate = navigation
        self.retainedObservers.append(navigation)
        self.activeWebViews.append(webView)
        webView.loadHTMLString(html, baseURL: URL(string: "https://measurement.test/list"))
        try await navigation.waitForFinish()

        let waiter: WKWebViewDOMStabilityWaiter = WKWebViewDOMStabilityWaiter(
            policy: .baseline,
            url: try XCTUnwrap(URL(string: "https://measurement.test/list"))
        )
        let outcome: WKWebViewDOMStabilityWaiter.Outcome = try await waiter.waitForStableDOM(in: webView, readinessSelector: selector)
        return (outcome, webView)
    }

    private static func count(of selector: String, in webView: WKWebView) async throws -> Int {
        let result: Any? = try await webView.evaluateJavaScript("document.querySelectorAll('\(selector)').length")
        if let count: Int = result as? Int {
            return count
        }
        return Int(try XCTUnwrap(result as? Double))
    }

    private static func report(_ fixture: String, baseline: WKWebViewDOMStabilityWaiter.Outcome, gated: WKWebViewDOMStabilityWaiter.Outcome) {
        print(
            "[readiness-selector measurement] fixture=\(fixture) " +
            "baseline=\(baseline.waited.milliseconds)ms(\(baseline.reason.rawValue),checks=\(baseline.observedChecks)) " +
            "selector=\(gated.waited.milliseconds)ms(\(gated.reason.rawValue),checks=\(gated.observedChecks),matched=\(gated.matchedCount.map(String.init) ?? "-"))"
        )
    }

    override func tearDown() async throws {
        for webView: WKWebView in self.activeWebViews {
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.loadHTMLString("", baseURL: nil)
        }
        self.activeWebViews.removeAll()
        self.retainedObservers.removeAll()
        try await super.tearDown()
    }

    private var retainedObservers: [NavigationObserver] = []
    private var activeWebViews: [WKWebView] = []

    @MainActor
    private final class NavigationObserver: NSObject, WKNavigationDelegate {
        private var continuation: CheckedContinuation<Void, Error>?
        private var hasFinished: Bool = false

        func waitForFinish() async throws {
            if self.hasFinished {
                return
            }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.continuation = continuation
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            self.hasFinished = true
            self.continuation?.resume()
            self.continuation = nil
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: Error) {
            self.continuation?.resume(throwing: error)
            self.continuation = nil
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: Error) {
            self.continuation?.resume(throwing: error)
            self.continuation = nil
        }
    }
}
