import BrowseCraftDomain
import Foundation

struct ChromeRequestHeaderProvider: BrowserRequestHeaderProviding {
    let userAgent: String = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36"

    private let chromeMajorVersion: String = "150"

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
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
            "Accept-Language": self.acceptLanguage,
            "Cache-Control": "no-cache",
            "Pragma": "no-cache",
            "Priority": "u=0, i",
            "Sec-CH-UA": "\"Not;A=Brand\";v=\"8\", \"Chromium\";v=\"\(self.chromeMajorVersion)\", \"Google Chrome\";v=\"\(self.chromeMajorVersion)\"",
            "Sec-CH-UA-Mobile": "?0",
            "Sec-CH-UA-Platform": "\"macOS\"",
            "Sec-Fetch-Dest": "document",
            "Sec-Fetch-Mode": "navigate",
            "Sec-Fetch-Site": "none",
            "Sec-Fetch-User": "?1",
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
