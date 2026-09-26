import BrowseCraftDomain
import Foundation

/// 中文注释：`BC-ACQ-070`——App 默认请求头是 App 自己的真实身份：苹果网络栈（URLSession / WKWebView），即 Safari。
///
/// 此前这里是一整套**桌面 Chrome** 请求头（`BC-ACQ-059`，2026-09-19）。2026-09-26 模拟器实测：WKWebView
/// 自称 Chrome 时多数 Cloudflare 挑战站过不去，改用 Safari UA 后多数能自动通过；线上九个来源换成桌面 Safari
/// 不换模板。因此 UA 取桌面 Safari（单一定义点 `ClientUserAgent.desktopSafari`），并去掉 Chrome 专有、
/// Safari 不会发的头：`Sec-CH-UA` 三件、`Priority`、`Sec-Fetch-User`。`Accept` 取 Safari 的取值，
/// 引擎第十二闸门从本文件核对它与引擎 `RUNTIME_DEFAULT_ACCEPT` 逐字相同。
struct SafariRequestHeaderProvider: BrowserRequestHeaderProviding {
    let userAgent: String = ClientUserAgent.desktopSafari

    /// `BC-ACQ-062`：语言这一格按**设备/用户的实际地区**来，不写死。
    ///
    /// 中文注释：此前这里是常量 `zh-CN,zh;q=0.9,zh-TW;q=0.8,en;q=0.7`，繁中用户也被按简中
    /// 对待——WEBTOON 对简中返回 `Error Language` 页、对繁中才返回正文。取值与提交给服务端的
    /// `acceptLanguage` 同源（`DeviceAcceptLanguage`），预检、提交、运行时因此到达同一个页面。
    /// 设备一个可用标签都给不出时回落到这个常量：它是「未指定地区」的表达，与引擎侧
    /// `RUNTIME_DEFAULT_ACCEPT_LANGUAGE` 逐字相同。
    static let unspecifiedLocaleAcceptLanguage: String =
        "zh-CN,zh;q=0.9,zh-TW;q=0.8,en;q=0.7"

    private let deviceAcceptLanguage: DeviceAcceptLanguage

    init(deviceAcceptLanguage: DeviceAcceptLanguage = DeviceAcceptLanguage()) {
        self.deviceAcceptLanguage = deviceAcceptLanguage
    }

    /// 随请求发给服务端的那一份（`PortalRuleGenerationRequest.acceptLanguage`）。
    var acceptLanguage: String {
        return self.deviceAcceptLanguage.value()
            ?? Self.unspecifiedLocaleAcceptLanguage
    }

    func defaultHeaders(
        for url: URL,
        referer: URL?,
        includeOrigin: Bool
    ) -> [String: String] {
        var headers: [String: String] = [
            "User-Agent": self.userAgent,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": self.acceptLanguage,
            "Cache-Control": "no-cache",
            "Pragma": "no-cache",
            "Sec-Fetch-Dest": "document",
            "Sec-Fetch-Mode": "navigate",
            "Sec-Fetch-Site": "none",
            "Upgrade-Insecure-Requests": "1"
        ]
        if let referer: URL {
            headers["Referer"] = referer.absoluteString
        }
        if includeOrigin,
           let origin: String = RequestHeaderFields.originHeader(from: referer ?? url) {
            headers["Origin"] = origin
        }
        return headers
    }
}
