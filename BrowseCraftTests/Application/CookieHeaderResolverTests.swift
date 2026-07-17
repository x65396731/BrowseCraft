import Foundation
import Testing
@testable import BrowseCraft

// 中文注释：CookieHeaderResolver 测试，确认 RequestConfig 的 Cookie 策略在不依赖真实浏览器状态时也能稳定验证。
struct CookieHeaderResolverTests {
    @Test func customPolicyUsesRuleCookieHeaderOnly() throws {
        let headers: [String: String] = CookieHeaderResolver.headersByApplyingCookies(
            to: ["Cookie": "session=rule; theme=dark"],
            url: try #require(URL(string: "https://example.test")),
            cookiePolicy: .custom,
            cookiePriority: .custom,
            browserCookieHeader: "session=browser; token=abc"
        )

        // 中文注释：custom 策略只信任规则 header 里的 Cookie，不混入浏览器 Cookie。
        #expect(headers["Cookie"] == "session=rule; theme=dark")
    }

    @Test func browserPolicyUsesBrowserCookieHeaderOnly() throws {
        let headers: [String: String] = CookieHeaderResolver.headersByApplyingCookies(
            to: ["Cookie": "session=rule; theme=dark"],
            url: try #require(URL(string: "https://example.test")),
            cookiePolicy: .browser,
            cookiePriority: .browser,
            browserCookieHeader: "session=browser; token=abc"
        )

        // 中文注释：browser 策略应覆盖规则 Cookie，便于需要真实浏览器会话的站点复用登录态。
        #expect(headers["Cookie"] == "session=browser; token=abc")
    }

    @Test func browserPolicyUsesCredentialCookieBeforeGlobalBrowserCookie() throws {
        let headers: [String: String] = CookieHeaderResolver.headersByApplyingCookies(
            to: ["Cookie": "session=rule; theme=dark"],
            url: try #require(URL(string: "https://example.test")),
            cookiePolicy: .browser,
            cookiePriority: .browser,
            browserCookieHeader: "session=browser; token=abc",
            credentialCookieHeader: "session=credential; member=yes"
        )

        // 中文注释：按 source 保存的登录态比全局浏览器 Cookie 更精确，同名 Cookie 应优先生效。
        #expect(headers["Cookie"] == "token=abc; session=credential; member=yes")
    }

    @Test func browserThenCustomMergesCookiesWithCustomPriority() throws {
        let headers: [String: String] = CookieHeaderResolver.headersByApplyingCookies(
            to: ["Cookie": "session=rule; theme=dark"],
            url: try #require(URL(string: "https://example.test")),
            cookiePolicy: .browserThenCustom,
            cookiePriority: .custom,
            browserCookieHeader: "session=browser; token=abc"
        )

        // 中文注释：custom 优先时，同名 Cookie 使用规则值，浏览器独有 Cookie 继续保留。
        #expect(headers["Cookie"] == "token=abc; session=rule; theme=dark")
    }

    @Test func browserThenCustomMergesCredentialCookiesWithCustomPriority() throws {
        let headers: [String: String] = CookieHeaderResolver.headersByApplyingCookies(
            to: ["Cookie": "session=rule; theme=dark"],
            url: try #require(URL(string: "https://example.test")),
            cookiePolicy: .browserThenCustom,
            cookiePriority: .custom,
            browserCookieHeader: "session=browser; token=abc",
            credentialCookieHeader: "session=credential; member=yes"
        )

        // 中文注释：规则 Cookie 优先时，credential/global browser 的独有 Cookie 仍会保留。
        #expect(headers["Cookie"] == "token=abc; member=yes; session=rule; theme=dark")
    }

    @Test func browserThenCustomMergesCookiesWithBrowserPriority() throws {
        let headers: [String: String] = CookieHeaderResolver.headersByApplyingCookies(
            to: ["Cookie": "session=rule; theme=dark"],
            url: try #require(URL(string: "https://example.test")),
            cookiePolicy: .browserThenCustom,
            cookiePriority: .browser,
            browserCookieHeader: "session=browser; token=abc"
        )

        // 中文注释：browser 优先时，同名 Cookie 使用浏览器值，规则独有 Cookie 继续保留。
        #expect(headers["Cookie"] == "theme=dark; session=browser; token=abc")
    }

    @Test func browserThenCustomMergesCredentialCookiesWithBrowserPriority() throws {
        let headers: [String: String] = CookieHeaderResolver.headersByApplyingCookies(
            to: ["Cookie": "session=rule; theme=dark"],
            url: try #require(URL(string: "https://example.test")),
            cookiePolicy: .browserThenCustom,
            cookiePriority: .browser,
            browserCookieHeader: "session=browser; token=abc",
            credentialCookieHeader: "session=credential; member=yes"
        )

        // 中文注释：browser 优先语义下，按 source 的 credential Cookie 先合入 browser-like 层。
        #expect(headers["Cookie"] == "theme=dark; token=abc; session=credential; member=yes")
    }

    @Test func nonePolicyRemovesCookieHeader() throws {
        let headers: [String: String] = CookieHeaderResolver.headersByApplyingCookies(
            to: ["Cookie": "session=rule"],
            url: try #require(URL(string: "https://example.test")),
            cookiePolicy: CookiePolicy.none,
            cookiePriority: CookiePriority.none,
            browserCookieHeader: "session=browser"
        )

        // 中文注释：明确 none 时要移除 Cookie，避免规则需要无状态请求时被浏览器状态污染。
        #expect(headers["Cookie"] == nil)
    }
}
