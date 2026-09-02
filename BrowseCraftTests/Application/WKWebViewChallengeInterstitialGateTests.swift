import Foundation
import XCTest
@testable import BrowseCraft

/// 中文注释：`BC-EVIDENCE-081` 加载器决策状态机——不依赖 WebKit 的确定性验证。
/// 真实站上 Cloudflare 是否出题取决于指纹/信誉（09-03 jable r4/r5 均未被出题），
/// 所以「过渡页不返回、首次延时一次、仍是过渡页 typed 失败」在这里锁定。
final class WKWebViewChallengeInterstitialGateTests: XCTestCase {
    private let challengeHTML: String = """
    <html><head><title>Just a moment...</title></head><body>
    <script>window._cf_chl_opt={cvId:'3'};</script>
    <script src="/cdn-cgi/challenge-platform/h/b/orchestrate/chl_page/v1"></script></body></html>
    """
    private let documentHTML: String = "<html><body><h1>ATID-636</h1><video id=\"player\"></video></body></html>"
    private let url: URL = URL(string: "https://example.invalid/videos/atid-636/")!

    func testDocumentIsReturnedImmediately() {
        var gate: WKWebViewChallengeInterstitialGate = WKWebViewChallengeInterstitialGate()
        XCTAssertEqual(gate.evaluate(renderedHTML: self.documentHTML), .document)
        XCTAssertFalse(gate.challengeInterstitialObserved)
        if case .timedOut = gate.timeoutError(url: self.url, seconds: 12) {} else {
            XCTFail("未观察过过渡页时到期应是普通超时")
        }
    }

    func testFirstInterstitialWaitsAndExtendsOnce() {
        var gate: WKWebViewChallengeInterstitialGate = WKWebViewChallengeInterstitialGate()
        XCTAssertEqual(
            gate.evaluate(renderedHTML: self.challengeHTML),
            .waitForNextNavigation(
                extendTimeoutSeconds: WKWebViewChallengeInterstitialGate.challengeTimeoutSeconds
            )
        )
        // 第二次仍是过渡页：继续等待，但不再延时
        XCTAssertEqual(
            gate.evaluate(renderedHTML: self.challengeHTML),
            .waitForNextNavigation(extendTimeoutSeconds: nil)
        )
        // 挑战脚本二次导航到真页：放行
        XCTAssertEqual(gate.evaluate(renderedHTML: self.documentHTML), .document)
    }

    func testUnresolvedInterstitialBecomesTypedFailure() {
        var gate: WKWebViewChallengeInterstitialGate = WKWebViewChallengeInterstitialGate()
        _ = gate.evaluate(renderedHTML: self.challengeHTML)
        switch gate.timeoutError(url: self.url, seconds: 30) {
        case .challengeInterstitialUnresolved(let failedURL, let seconds):
            XCTAssertEqual(failedURL, self.url)
            XCTAssertEqual(seconds, 30)
        default:
            XCTFail("观察过过渡页后到期必须是 challengeInterstitialUnresolved")
        }
    }
}
