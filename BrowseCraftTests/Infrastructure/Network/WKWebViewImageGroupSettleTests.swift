import BrowseCraftDomain
import WebKit
import XCTest
@testable import BrowseCraft

// 中文注释：`APP-MEMO-016`（`BC-COMIC-127` ⑤）的固定输入用例。页面用 loadHTMLString 注入，不访问真实站点。
//
// 被测事实：漫画阅读页的图片由脚本分批追加，整页 outerHTML 长度会先安静下来。历史的长度判稳因此在图片
// 到齐之前就交出 DOM——manga18 `rooftop-sex-king/chapter-83` 实测：规则生成引擎按同一结构条件取到 8 张，
// App 只拿到 6 张（2026-09-18，模拟器）。声明 `.imageGroupStable` 之后按「带地址属性的 <img> 总数不再增长」判定。
@MainActor
final class WKWebViewImageGroupSettleTests: XCTestCase {
    private enum Fixture {
        /// 中文注释：manga18 的形态——正文图片每 400ms 追加一张，共 8 张；DOM 长度在每批之间是安静的。
        static let lateAppendedImages: String = """
        <html><body>
          <div id="chapter_boxImages"></div>
          <script>
            let index = 0;
            const timer = setInterval(() => {
              index += 1;
              const image = document.createElement("img");
              image.setAttribute("src", "https://cdn.example.test/page-" + index + ".jpg");
              document.getElementById("chapter_boxImages").appendChild(image);
              if (index >= 8) { clearInterval(timer); }
            }, 400);
          </script>
        </body></html>
        """

        /// 中文注释：没有图片的页面——条件不得让它白等满上限。
        static let noImages: String = """
        <html><body><div id="content">纯文字</div></body></html>
        """

        /// 中文注释：占位图先出现、随后被脚本回收（总数下降）。「不增长」而不是「相等」才判得对。
        static let shrinkingImages: String = """
        <html><body>
          <div id="box">
            <img src="https://cdn.example.test/a.jpg"><img src="https://cdn.example.test/b.jpg">
            <img src="https://cdn.example.test/c.jpg"><img src="https://cdn.example.test/d.jpg">
          </div>
          <script>
            setTimeout(() => {
              const box = document.getElementById("box");
              box.removeChild(box.lastElementChild);
            }, 300);
          </script>
        </body></html>
        """

        /// 中文注释：带地址属性的才算——静态装饰用的空 `<img>` 不计入。
        static let addresslessImages: String = """
        <html><body>
          <img><img><img>
          <div id="box"><img src="https://cdn.example.test/only.jpg"></div>
        </body></html>
        """
    }

    /// 中文注释：本条的核心——分批追加的 8 张必须全部到齐才返回，长度判稳会在此之前交卷。
    func testAllLateAppendedImagesArePresentWhenSettled() async throws {
        let webView: WKWebView = try await self.loadedWebView(Fixture.lateAppendedImages)
        let outcome: WKWebViewDOMStabilityWaiter.Outcome = try await self.waiter().waitForStableDOM(
            in: webView,
            settleCondition: .imageGroupStable
        )
        let count: Int = try await Self.addressedImageCount(in: webView)

        print("[APP-MEMO-016] lateAppended reason=\(outcome.reason.rawValue) waitedMs=\(outcome.waited.milliseconds) count=\(count)")
        XCTAssertEqual(outcome.reason, .settled)
        XCTAssertEqual(count, 8, "返回时 8 张必须都在 DOM 里")
        XCTAssertEqual(outcome.matchedCount, 8)
    }

    /// 中文注释：同一份固定输入下，历史的长度判稳拿不到 8 张——这就是缺口本身。
    func testRenderedLengthPollingWouldReturnEarly() async throws {
        let webView: WKWebView = try await self.loadedWebView(Fixture.lateAppendedImages)
        _ = try await self.waiter().waitForStableDOM(in: webView)
        let count: Int = try await Self.addressedImageCount(in: webView)

        print("[APP-MEMO-016] renderedLengthPolling count=\(count)")
        XCTAssertLessThan(count, 8, "长度判稳在图片到齐前返回，正是本条要修的缺口")
    }

    /// 中文注释：零张图的页面在两次采样后就安定，不得白等满 12 s 上限。
    func testPageWithoutImagesSettlesQuickly() async throws {
        let webView: WKWebView = try await self.loadedWebView(Fixture.noImages)
        let outcome: WKWebViewDOMStabilityWaiter.Outcome = try await self.waiter().waitForStableDOM(
            in: webView,
            settleCondition: .imageGroupStable
        )

        XCTAssertEqual(outcome.reason, .settled)
        XCTAssertEqual(outcome.matchedCount, 0)
        XCTAssertLessThan(outcome.waited.milliseconds, 6_000, "零张图不得等满保护上限")
    }

    /// 中文注释：总数下降也算安定——判据是「不增长」，不是「相等」。
    func testShrinkingImageCountStillSettles() async throws {
        let webView: WKWebView = try await self.loadedWebView(Fixture.shrinkingImages)
        let outcome: WKWebViewDOMStabilityWaiter.Outcome = try await self.waiter().waitForStableDOM(
            in: webView,
            settleCondition: .imageGroupStable
        )

        XCTAssertEqual(outcome.reason, .settled)
        XCTAssertEqual(outcome.matchedCount, 3)
    }

    /// 中文注释：不带地址属性的 `<img>` 不计入总数。
    func testOnlyImagesCarryingAnAddressAreCounted() async throws {
        let webView: WKWebView = try await self.loadedWebView(Fixture.addresslessImages)
        let outcome: WKWebViewDOMStabilityWaiter.Outcome = try await self.waiter().waitForStableDOM(
            in: webView,
            settleCondition: .imageGroupStable
        )

        XCTAssertEqual(outcome.matchedCount, 1)
    }

    /// 中文注释：安定上限必须严格小于声明了条件时的总超时——否则等待被外层超时抢跑。
    /// 2026-09-18 真机日志两行同时出现（`timeout after 12.0s, using current DOM` 与
    /// `dom-stability reason=settled waitedMs=11397`）就是两者同为 12 s 的后果。
    func testSettleCapLeavesHeadroomUnderTheLoaderTimeout() {
        let cap: Int = WKWebViewDOMStabilityPolicy.ImageGroupStability.baseline.maximumWait.milliseconds
        XCTAssertEqual(cap, 12_000)
        XCTAssertLessThan(cap, Int(WKWebViewHTMLLoaderTimingProbe.settleConditionTimeoutSeconds * 1_000))
        XCTAssertEqual(WKWebViewHTMLLoaderTimingProbe.settleConditionTimeoutSeconds, 17)
    }

    /// 中文注释：取值与规则生成引擎的常量同值——两侧是同一条结构条件，不是各调各的秒数。
    func testBaselineMatchesTheEngineConstants() {
        let baseline: WKWebViewDOMStabilityPolicy.ImageGroupStability = .baseline
        XCTAssertEqual(baseline.sampleInterval, .milliseconds(1_000))
        XCTAssertEqual(baseline.requiredNonIncreasingSamples, 2)
        XCTAssertEqual(baseline.maximumWait, .seconds(12))
        XCTAssertEqual(PageContentSettleCondition.allCases, [.imageGroupStable])
    }

    /// 中文注释：没有声明条件的请求走历史判定，逐字不变。
    func testUndeclaredRequestsKeepTheHistoricalMechanism() async throws {
        let webView: WKWebView = try await self.loadedWebView(Fixture.noImages)
        let outcome: WKWebViewDOMStabilityWaiter.Outcome = try await self.waiter().waitForStableDOM(in: webView)

        XCTAssertEqual(outcome.reason, .quiet)
        XCTAssertNil(outcome.matchedCount)
    }

    // MARK: - 装置

    private var activeWebViews: [WKWebView] = []
    private var retainedObservers: [NavigationObserver] = []

    override func tearDown() async throws {
        self.activeWebViews.removeAll()
        self.retainedObservers.removeAll()
        try await super.tearDown()
    }

    private func waiter() -> WKWebViewDOMStabilityWaiter {
        return WKWebViewDOMStabilityWaiter(
            policy: .baseline,
            url: URL(string: "https://measurement.test/chapter")!
        )
    }

    private static func addressedImageCount(in webView: WKWebView) async throws -> Int {
        let result: Any? = try await webView.evaluateJavaScript(
            """
            (() => {
              let total = 0;
              for (const image of document.images) {
                if (image.getAttribute('src') || image.getAttribute('data-src') || image.getAttribute('data-original')) {
                  total += 1;
                }
              }
              return total;
            })();
            """
        )
        if let count: Int = result as? Int { return count }
        if let count: Double = result as? Double { return Int(count) }
        return -1
    }

    private func loadedWebView(_ html: String) async throws -> WKWebView {
        let webView: WKWebView = WKWebView(frame: .zero)
        let navigation: NavigationObserver = NavigationObserver()
        webView.navigationDelegate = navigation
        self.retainedObservers.append(navigation)
        self.activeWebViews.append(webView)
        webView.loadHTMLString(html, baseURL: URL(string: "https://measurement.test/chapter"))
        try await navigation.waitForFinish()
        return webView
    }

    /// 中文注释：把 didFinish 桥接成一次 await，测量只从「页面加载完成」那一刻开始计时。
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
