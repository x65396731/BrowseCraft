import Foundation
import XCTest
@testable import BrowseCraft

final class VideoPreflightPageClassifierTests: XCTestCase {
    func testScriptOnlyShellRequiresRenderedFallback() {
        let page: PreflightAcquiredPage = self.page(
            "<html><body><div id=\"app\"></div><script src=\"app.js\"></script></body></html>"
        )

        XCTAssertEqual(VideoPreflightPageClassifier().classify(page), .technicalShell)
    }

    func testLoginAndAntiBotRemainDifferentEvidenceStates() {
        let login: PreflightAcquiredPage = self.page(
            "<html><body><form>Log in<input type=\"password\"></form></body></html>"
        )
        let antiBot: PreflightAcquiredPage = self.page(
            "<html><body>Just a moment. Verify you are human.<div class=\"cf-chl-box\"></div></body></html>"
        )

        XCTAssertEqual(VideoPreflightPageClassifier().classify(login), .requiresUserSession)
        XCTAssertEqual(VideoPreflightPageClassifier().classify(antiBot), .antiBotChallenge)
    }

    /// `BC-PREFLIGHT-049`：内容页上的登录小组件不构成登录页。
    func testContentPageWithLoginWidgetIsUsableHTML() {
        let anchors: String = (1...40).map { index in
            "<div class=\"card\"><a href=\"/films/\(index)-title.html\">Title \(index) with a longer caption text</a></div>"
        }.joined()
        let html: String = "<html><body><aside><form>Login<input type=\"password\"></form></aside>" +
            "<div id=\"content\">\(anchors)</div></body></html>"

        XCTAssertEqual(VideoPreflightPageClassifier().classify(self.page(html)), .usableHTML)
    }

    private func page(_ html: String) -> PreflightAcquiredPage {
        let url: URL = URL(string: "https://example.com/list")!
        return PreflightAcquiredPage(
            requestedURL: url,
            data: Data(html.utf8),
            finalURL: url,
            mediaType: "text/html",
            textEncodingName: "utf-8",
            acquisitionIdentity: UUID().uuidString,
            source: .http,
            isolationScope: .fullHTTP
        )
    }
}
