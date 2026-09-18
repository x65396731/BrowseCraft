import WebKit
import XCTest
@testable import BrowseCraft

// 中文注释：F2-7 的固定输入测量。不访问真实站点，页面用 loadHTMLString 注入，结果与网络无关。
//
// 两条被测量推翻的假设，结论写在 Documentation/Audit 里：
// 1. 历史机制的「最少观察 6 轮」（约 1500ms 下限）不是浪费，而是一条没写下来的不变量：
//    页面可能在 didFinish 之后先安静一段再用定时器写入正文，只看「连续 300ms 无变更」会在 300ms
//    就判定稳定并交出空正文。`testMinimumSettleFloorIsLoadBearing` 守住这条。
// 2. 离屏 WKWebView（frame .zero、从未进入 window）会节流页面内的定时器，因此任何跑在页面里的
//    计时循环都不可靠；判定节奏必须留在 Swift 侧。`testOffscreenWebViewThrottlesInPageTimers` 记录这一点。
//
// 在此之上，原以为可省的「每轮整页 `outerHTML` 序列化」实测也不构成开销：
// 662KB 的 DOM 上 6 次序列化共约 6ms。`testRepeatedOuterHTMLSerialisationCost` 守住这个量级，
// 若某次改动让它显著变大，说明假设变了、需要重新评估。
@MainActor
final class WKWebViewDOMStabilityMeasurementTests: XCTestCase {
    private enum Fixture {
        static let quiet: String = """
        <html><body><div id="content">static</div></body></html>
        """

        /// 中文注释：加载完 800ms 后才写入正文，之后不再变更。
        static let lateContent: String = """
        <html><body><div id="content"></div>
        <script>
          setTimeout(() => {
            document.getElementById("content").innerHTML = "<p>" + "x".repeat(4000) + "</p>";
          }, 800);
        </script>
        </body></html>
        """

        /// 中文注释：约 1500 个节点、约 250KB 的 DOM，用来量化整页序列化的代价。
        /// 不取更大：测量用例与整套测试同进程，WebView 越多越容易把测试宿主推到内存上限被 SIGKILL。
        static let largeQuietDOM: String = {
            let rows: String = (0..<1_500).map { index in
                "<p class=\"row\" data-index=\"\(index)\">row \(index) " + String(repeating: "z", count: 120) + "</p>"
            }.joined()
            return "<html><body><div id=\"content\">" + rows + "</div></body></html>"
        }()
    }

    /// 中文注释：历史机制在正文出现之前不得判定稳定——这是它 1500ms 下限的真正作用。
    func testMinimumSettleFloorIsLoadBearing() async throws {
        let webView: WKWebView = try await self.loadedWebView(Fixture.lateContent)
        let outcome: WKWebViewDOMStabilityWaiter.Outcome = try await self.waiter(.baseline).waitForStableDOM(in: webView)
        let renderedLength: Int = try await Self.outerHTMLLength(in: webView)

        print("[F2-7 measurement] lateContent baseline=\(outcome.waited.milliseconds)ms checks=\(outcome.observedChecks) renderedLength=\(renderedLength)")
        XCTAssertGreaterThanOrEqual(outcome.waited.milliseconds, 800, "判定稳定的时刻不得早于正文写入")
        XCTAssertGreaterThan(renderedLength, 4_000, "返回时正文必须已经在 DOM 里")
    }

    /// 中文注释：记录离屏 WebView 的定时器节流事实——页面内 50ms 的 setTimeout 实际间隔远大于 50ms。
    func testOffscreenWebViewThrottlesInPageTimers() async throws {
        let webView: WKWebView = try await self.loadedWebView(Fixture.quiet)
        let start: ContinuousClock.Instant = ContinuousClock.now
        let result: Any? = try await webView.callAsyncJavaScript(
            """
            const startedAt = Date.now();
            let ticks = 0;
            while (Date.now() - startedAt < 1000) {
              ticks += 1;
              await new Promise((resolve) => { setTimeout(resolve, 50); });
            }
            return { ticks: ticks, elapsedMs: Date.now() - startedAt };
            """,
            arguments: [:],
            contentWorld: .defaultClient
        )
        let payload: [String: Any] = try XCTUnwrap(result as? [String: Any])
        let ticks: Int = try XCTUnwrap(payload["ticks"] as? Int)
        let elapsed: Int = try XCTUnwrap(payload["elapsedMs"] as? Int)
        let perTick: Int = ticks > 0 ? elapsed / ticks : 0

        print("[F2-7 measurement] offscreenTimerThrottling requested=50ms actual=\(perTick)ms ticks=\(ticks) wallClock=\((ContinuousClock.now - start).milliseconds)ms")
        XCTAssertGreaterThan(ticks, 0)
        // 只记录事实、不锁死具体倍数：实测远大于请求值，说明页面内计时不可作为判定节奏。
        XCTAssertGreaterThan(perTick, 50)
    }

    /// 中文注释：量化每轮整页 `outerHTML.length` 的代价——这是历史机制唯一可去掉的开销。
    ///
    /// 断言取「文档越大、整页序列化越贵」这条不变量，而不是「序列化比空转 JS 贵」。
    /// 后者 2026-09-18 在小页面上翻转过一次（1ms 对 2ms）：两者都由 JS 桥往返的固定开销主导，
    /// 毫秒取整之后谁大谁小是噪声。**`Duration.milliseconds` 的注释本就写明「只用于日志与测量输出，
    /// 不参与判断」，那条断言违反了它自己的约定。** 现在改为直接比较两个夹具的 `Duration`：
    /// JS 桥的固定开销在两边相同、会被抵消，剩下的差异只来自文档大小。
    func testRepeatedOuterHTMLSerialisationCost() async throws {
        var serialisationByFixture: [String: Duration] = [:]
        for (label, html) in [("smallDOM", Fixture.quiet), ("largeDOM", Fixture.largeQuietDOM)] {
            let webView: WKWebView = try await self.loadedWebView(html)
            let documentLength: Int = try await Self.outerHTMLLength(in: webView)

            let serialisationStart: ContinuousClock.Instant = ContinuousClock.now
            for _ in 0..<6 {
                _ = try await Self.outerHTMLLength(in: webView)
            }
            let serialisation: Duration = ContinuousClock.now - serialisationStart

            let trivialStart: ContinuousClock.Instant = ContinuousClock.now
            for _ in 0..<6 {
                _ = try await webView.evaluateJavaScript("1")
            }
            let trivial: Duration = ContinuousClock.now - trivialStart

            print(
                "[F2-7 measurement] fixture=\(label) documentLength=\(documentLength) " +
                "sixOuterHTMLLengthEvals=\(serialisation.milliseconds)ms sixTrivialEvals=\(trivial.milliseconds)ms " +
                "serialisationOverhead=\(serialisation.milliseconds - trivial.milliseconds)ms"
            )
            serialisationByFixture[label] = serialisation
        }

        let small: Duration = try XCTUnwrap(serialisationByFixture["smallDOM"])
        let large: Duration = try XCTUnwrap(serialisationByFixture["largeDOM"])
        XCTAssertGreaterThan(large, small, "1500 行的文档整页序列化必须比小页面贵")
    }

    /// 中文注释：小页面上历史机制的等待时长，作为下限基线记录。
    func testBaselineWaitOnAQuietPage() async throws {
        let webView: WKWebView = try await self.loadedWebView(Fixture.quiet)
        let outcome: WKWebViewDOMStabilityWaiter.Outcome = try await self.waiter(.baseline).waitForStableDOM(in: webView)

        print("[F2-7 measurement] quiet baseline=\(outcome.waited.milliseconds)ms checks=\(outcome.observedChecks) reason=\(outcome.reason.rawValue)")
        XCTAssertEqual(outcome.reason, .quiet)
        XCTAssertEqual(outcome.observedChecks, 6, "最少观察轮数决定了固定下限")
    }

    // MARK: - 测量夹具

    private func waiter(_ policy: WKWebViewDOMStabilityPolicy) throws -> WKWebViewDOMStabilityWaiter {
        return WKWebViewDOMStabilityWaiter(
            policy: policy,
            url: URL(string: "https://measurement.test/page")!
        )
    }

    private static func outerHTMLLength(in webView: WKWebView) async throws -> Int {
        let result: Any? = try await webView.evaluateJavaScript("document.documentElement.outerHTML.length")
        if let length: Int = result as? Int {
            return length
        }
        return Int(try XCTUnwrap(result as? Double))
    }

    /// 中文注释：每个 WebView 用完即拆——测量用例与整套测试同进程，残留的 WebContent 进程会累积内存，
    /// 此前一次全量运行里测试宿主被 SIGKILL，随机牵连到当时正在跑的其它用例。
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

    private func loadedWebView(_ html: String) async throws -> WKWebView {
        let webView: WKWebView = WKWebView(frame: .zero)
        let navigation: NavigationObserver = NavigationObserver()
        webView.navigationDelegate = navigation
        self.retainedObservers.append(navigation)
        self.activeWebViews.append(webView)
        webView.loadHTMLString(html, baseURL: URL(string: "https://measurement.test/page"))
        try await navigation.waitForFinish()
        return webView
    }

    private var retainedObservers: [NavigationObserver] = []
    private var activeWebViews: [WKWebView] = []

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
