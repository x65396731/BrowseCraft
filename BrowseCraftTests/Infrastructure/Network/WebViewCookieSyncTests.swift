import Foundation
import XCTest
@testable import BrowseCraft

/// 中文注释：2026-10-07 xbanxia——WebView 过挑战拿到的 `.xbanxia.cc` 放行 Cookie 要对 `image.xbanxia.cc` 生效。
final class WebViewCookieSyncTests: XCTestCase {
    private func cookie(_ name: String, domain: String) -> HTTPCookie {
        return HTTPCookie(properties: [.name: name, .value: "v", .domain: domain, .path: "/"])!
    }

    func testZoneCookieAppliesToSiblingSubdomainsButNotOtherSites() {
        let cookies: [HTTPCookie] = [
            self.cookie("cf_clearance", domain: ".xbanxia.cc"),
            self.cookie("session", domain: "www.xbanxia.cc"),
            self.cookie("other", domain: ".example.com"),
            self.cookie("lookalike", domain: "notxbanxia.cc"),
        ]
        let names: [String] = WebViewCookieSync.cookiesApplying(to: "www.xbanxia.cc", from: cookies).map(\.name)
        XCTAssertEqual(names, ["cf_clearance", "session"])
    }

    func testCopiedZoneCookieIsSentToTheImageHost() {
        let storage: HTTPCookieStorage = HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: "WebViewCookieSyncTests")
        storage.cookies?.forEach(storage.deleteCookie)
        let copied: Int = WebViewCookieSync.copy(
            [self.cookie("cf_clearance", domain: ".xbanxia.cc")],
            applyingTo: URL(string: "https://www.xbanxia.cc/list/2_1.html")!,
            into: storage
        )
        XCTAssertEqual(copied, 1)
        let imageCookies: [HTTPCookie] = storage.cookies(for: URL(string: "https://image.xbanxia.cc/files/a.jpg")!) ?? []
        XCTAssertEqual(imageCookies.map(\.name), ["cf_clearance"])
    }
}
