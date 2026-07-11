import Foundation

// 中文注释：CookieHeaderResolver.swift 集中处理 RequestConfig 的 Cookie header 合并，避免网络、WebView、图片请求各自实现一套规则。

enum BrowserRequestHeaders {
    struct Chrome {
        static let chromeUserAgent: String = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36"

        private static let chromeMajorVersion: String = "150"

        private init() {}

        static func defaultHeaders(for url: URL, referer: URL? = nil, includeOrigin: Bool = false) -> [String: String] {
            var headers: [String: String] = self.chromeHeaders
            if let referer: URL {
                headers["Referer"] = referer.absoluteString
            }
            if includeOrigin, let origin: String = BrowserRequestHeaders.originHeader(from: referer ?? url) {
                headers["Origin"] = origin
            }
            return headers
        }

        static func playbackHeaders(referer: URL) -> [String: String] {
            return self.defaultHeaders(for: referer, referer: referer, includeOrigin: true)
        }

        private static var chromeHeaders: [String: String] {
            return [
                "User-Agent": self.chromeUserAgent,
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
                "Accept-Language": "zh-CN,zh;q=0.9,zh-TW;q=0.8,en;q=0.7",
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
        }
    }

    static func applyingOverrides(
        _ overrides: [String: String]?,
        to headers: [String: String]
    ) -> [String: String] {
        var resolvedHeaders: [String: String] = headers
        overrides?.forEach { key, value in
            self.setHeader(key, value: value, in: &resolvedHeaders)
        }
        return resolvedHeaders
    }

    static func containsHeader(_ name: String, in headers: [String: String]) -> Bool {
        return headers.keys.contains { key in
            return key.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    static func originHeader(from url: URL?) -> String? {
        guard let url: URL,
              let scheme: String = url.scheme,
              let host: String = url.host else {
            return nil
        }

        var origin: String = "\(scheme)://\(host)"
        if let port: Int = url.port {
            origin += ":\(port)"
        }
        return origin
    }

    private static func setHeader(_ name: String, value: String, in headers: inout [String: String]) {
        if let existingKey: String = headers.keys.first(where: { key in
            return key.caseInsensitiveCompare(name) == .orderedSame
        }) {
            headers[existingKey] = value
        } else {
            headers[name] = value
        }
    }
}

enum APIRequestHeaders {
    static func isManagedAPIURL(_ url: URL) -> Bool {
        guard let host: String = url.host?.lowercased() else {
            return false
        }

        return host == "anyportal.online" || host.hasSuffix(".anyportal.online")
    }

    static func portalHeaders(
        userID: String,
        osInfo: String,
        deviceInfo: String,
        appVersion: String,
        requestID: String = UUID().uuidString
    ) -> [String: String] {
        return [
            "userId": userID,
            "osInfo": osInfo,
            "deviceInfo": deviceInfo,
            "aplVersion": appVersion,
            "X-Request-Id": requestID
        ]
    }

    static func catalogHeaders(base: [String: String]) -> [String: String] {
        var headers: [String: String] = base
        headers["Accept"] = "application/json"
        return headers
    }
}

/// 中文注释：P1-4.4 的 Cookie 执行器；当前只负责请求头合并，不引入登录态 UI 或复杂 CookieStore。
enum CookieHeaderResolver {
    /// 中文注释：页面 HTML 请求使用 RequestConfig 的 cookiePolicy/cookiePriority/cookieScope。
    static func headersByApplyingPageCookies(
        to headers: [String: String],
        url: URL,
        request: RequestConfig?
    ) -> [String: String] {
        return self.headersByApplyingCookies(
            to: headers,
            url: url,
            cookiePolicy: request?.cookiePolicy,
            cookiePriority: request?.cookiePriority,
            browserCookieHeader: self.browserCookieHeader(for: url)
        )
    }

    /// 中文注释：图片请求优先使用 imageRequest 的 Cookie 配置，未配置时继承页面 RequestConfig。
    static func headersByApplyingImageCookies(
        to headers: [String: String],
        url: URL,
        request: RequestConfig?
    ) -> [String: String] {
        return self.headersByApplyingCookies(
            to: headers,
            url: url,
            cookiePolicy: request?.imageRequest?.cookiePolicy ?? request?.cookiePolicy,
            cookiePriority: request?.imageRequest?.cookiePriority ?? request?.cookiePriority,
            browserCookieHeader: self.browserCookieHeader(for: url)
        )
    }

    /// 中文注释：测试入口；通过传入 browserCookieHeader 避免污染全局 HTTPCookieStorage。
    static func headersByApplyingCookies(
        to headers: [String: String],
        url: URL,
        cookiePolicy: CookiePolicy?,
        cookiePriority: CookiePriority?,
        browserCookieHeader: String?
    ) -> [String: String] {
        var resolvedHeaders: [String: String] = headers
        let customCookieHeader: String? = self.headerValue("Cookie", in: headers)
        let resolvedCookieHeader: String? = self.resolvedCookieHeader(
            cookiePolicy: cookiePolicy,
            cookiePriority: cookiePriority,
            customCookieHeader: customCookieHeader,
            browserCookieHeader: browserCookieHeader
        )

        self.removeHeader("Cookie", from: &resolvedHeaders)

        if let resolvedCookieHeader: String = resolvedCookieHeader,
           resolvedCookieHeader.isEmpty == false {
            resolvedHeaders["Cookie"] = resolvedCookieHeader
        }

        return resolvedHeaders
    }

    /// 中文注释：Cookie 合并的核心规则；customCookieHeader 来自规则 headers["Cookie"]。
    static func resolvedCookieHeader(
        cookiePolicy: CookiePolicy?,
        cookiePriority: CookiePriority?,
        customCookieHeader: String?,
        browserCookieHeader: String?
    ) -> String? {
        switch cookiePolicy {
        case .some(.none):
            return nil
        case .some(.custom):
            return customCookieHeader
        case .some(.browser):
            return browserCookieHeader
        case .some(.browserThenCustom):
            return self.mergedCookieHeader(
                customCookieHeader: customCookieHeader,
                browserCookieHeader: browserCookieHeader,
                cookiePriority: cookiePriority
            )
        case nil:
            return customCookieHeader
        }
    }

    /// 中文注释：同名 Cookie 冲突时按优先级决定；未指定时沿用 browserThenCustom 的名字，custom 覆盖 browser。
    private static func mergedCookieHeader(
        customCookieHeader: String?,
        browserCookieHeader: String?,
        cookiePriority: CookiePriority?
    ) -> String? {
        let customCookies: [(name: String, value: String)] = self.cookiePairs(from: customCookieHeader)
        let browserCookies: [(name: String, value: String)] = self.cookiePairs(from: browserCookieHeader)

        if customCookies.isEmpty {
            return browserCookieHeader
        }

        if browserCookies.isEmpty {
            return customCookieHeader
        }

        let customWins: Bool
        switch cookiePriority {
        case .some(.browser):
            customWins = false
        case .some(.none):
            return nil
        case .some(.custom), .some(.request), .some(.image), nil:
            customWins = true
        }

        let orderedPairs: [(name: String, value: String)] = customWins
            ? self.mergeCookiePairs(primary: customCookies, secondary: browserCookies)
            : self.mergeCookiePairs(primary: browserCookies, secondary: customCookies)

        return orderedPairs
            .map { pair in "\(pair.name)=\(pair.value)" }
            .joined(separator: "; ")
    }

    /// 中文注释：primary 优先，但输出顺序保留 secondary 中未冲突项在前，便于调试接近浏览器原始顺序。
    private static func mergeCookiePairs(
        primary: [(name: String, value: String)],
        secondary: [(name: String, value: String)]
    ) -> [(name: String, value: String)] {
        let primaryNames: Set<String> = Set(primary.map { pair in pair.name })
        let secondaryOnly: [(name: String, value: String)] = secondary.filter { pair in
            return primaryNames.contains(pair.name) == false
        }

        return secondaryOnly + primary
    }

    private static func cookiePairs(from cookieHeader: String?) -> [(name: String, value: String)] {
        guard let cookieHeader: String = cookieHeader else {
            return []
        }

        return cookieHeader
            .split(separator: ";")
            .compactMap { rawPair in
                let parts: [Substring] = rawPair.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else {
                    return nil
                }

                let name: String = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let value: String = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)

                guard name.isEmpty == false else {
                    return nil
                }

                return (name: name, value: value)
            }
    }

    private static func browserCookieHeader(for url: URL) -> String? {
        guard let cookies: [HTTPCookie] = HTTPCookieStorage.shared.cookies(for: url),
              cookies.isEmpty == false else {
            return nil
        }

        return cookies
            .map { cookie in "\(cookie.name)=\(cookie.value)" }
            .joined(separator: "; ")
    }

    private static func headerValue(_ name: String, in headers: [String: String]) -> String? {
        return headers.first { key, _ in
            return key.caseInsensitiveCompare(name) == .orderedSame
        }?.value
    }

    private static func removeHeader(_ name: String, from headers: inout [String: String]) {
        let matchingKeys: [String] = headers.keys.filter { key in
            return key.caseInsensitiveCompare(name) == .orderedSame
        }

        matchingKeys.forEach { key in
            headers.removeValue(forKey: key)
        }
    }
}
