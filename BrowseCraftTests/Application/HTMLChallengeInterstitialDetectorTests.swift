import Foundation
import XCTest
@testable import BrowseCraft

/// 中文注释：`BC-EVIDENCE-081`——挑战过渡页判据的唯一定义点。
/// 09-03 jable detail 实测：`403` + `<title>Just a moment...</title>` + `cf_chl_opt` + `challenge-platform`。
final class HTMLChallengeInterstitialDetectorTests: XCTestCase {
    func testCloudflareJavaScriptChallengeIsInterstitial() {
        let html: String = """
        <!DOCTYPE html><html lang="en-US"><head><title>Just a moment...</title>
        <meta http-equiv="refresh" content="360"></head>
        <body class="no-js"><div class="main-wrapper" role="main"><div class="main-content">
        <h1>jable.tv</h1><p>Verifying you are human. This may take a few seconds.</p></div></div>
        <script>window._cf_chl_opt={cvId:'3',cZone:"jable.tv",cType:'managed'};
        var a=document.createElement('script');a.src='/cdn-cgi/challenge-platform/h/b/orchestrate/chl_page/v1?ray=abc';
        document.getElementsByTagName('head')[0].appendChild(a);</script></body></html>
        """
        XCTAssertTrue(HTMLChallengeInterstitialDetector.isChallengeInterstitial(html))
    }

    func testSingleStrongMarkerIsEnough() {
        XCTAssertTrue(
            HTMLChallengeInterstitialDetector.isChallengeInterstitial(
                "<html><body><div class=\"cf-chl-box\"></div></body></html>"
            )
        )
    }

    func testWeakMarkersNeedTwoHits() {
        let single: String = "<html><body><p>Just a moment while we load your videos.</p></body></html>"
        let double: String = "<html><body>Just a moment. Verify you are human.</body></html>"
        XCTAssertFalse(HTMLChallengeInterstitialDetector.isChallengeInterstitial(single))
        XCTAssertTrue(HTMLChallengeInterstitialDetector.isChallengeInterstitial(double))
    }

    func testOrdinaryDetailPageIsNotInterstitial() {
        let html: String = """
        <html><head><title>ATID-636 - Jable</title></head><body>
        <video id="player" src="blob:https://jable.tv/abc"></video>
        <script>var hlsUrl = 'https://cdn.example/stream/index.m3u8';</script>
        <a href="/videos/atid-635/">Prev</a><a href="/videos/atid-637/">Next</a>
        </body></html>
        """
        XCTAssertFalse(HTMLChallengeInterstitialDetector.isChallengeInterstitial(html))
    }
}
