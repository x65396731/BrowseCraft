import Foundation

// 中文注释：CookieHeaderResolver 只合并调用方提供的 Cookie Header，不读取系统 Cookie 或其他外部状态。
enum CookieHeaderResolver {
    static func headersByApplyingPageCookies(
        to headers: [String: String],
        url: URL,
        request: RequestConfig?,
        browserCookieHeader: String?,
        credentialCookieHeader: String? = nil
    ) -> [String: String] {
        return self.headersByApplyingCookies(
            to: headers,
            url: url,
            cookiePolicy: request?.cookiePolicy,
            cookiePriority: request?.cookiePriority,
            browserCookieHeader: browserCookieHeader,
            credentialCookieHeader: credentialCookieHeader
        )
    }

    static func headersByApplyingImageCookies(
        to headers: [String: String],
        url: URL,
        request: RequestConfig?,
        browserCookieHeader: String?,
        credentialCookieHeader: String? = nil
    ) -> [String: String] {
        return self.headersByApplyingCookies(
            to: headers,
            url: url,
            cookiePolicy: request?.imageRequest?.cookiePolicy ?? request?.cookiePolicy,
            cookiePriority: request?.imageRequest?.cookiePriority ?? request?.cookiePriority,
            browserCookieHeader: browserCookieHeader,
            credentialCookieHeader: credentialCookieHeader
        )
    }

    static func headersByApplyingCookies(
        to headers: [String: String],
        url: URL,
        cookiePolicy: CookiePolicy?,
        cookiePriority: CookiePriority?,
        browserCookieHeader: String?
    ) -> [String: String] {
        return self.headersByApplyingCookies(
            to: headers,
            url: url,
            cookiePolicy: cookiePolicy,
            cookiePriority: cookiePriority,
            browserCookieHeader: browserCookieHeader,
            credentialCookieHeader: nil
        )
    }

    static func headersByApplyingCookies(
        to headers: [String: String],
        url: URL,
        cookiePolicy: CookiePolicy?,
        cookiePriority: CookiePriority?,
        browserCookieHeader: String?,
        credentialCookieHeader: String?
    ) -> [String: String] {
        var resolvedHeaders: [String: String] = headers
        let customCookieHeader: String? = self.headerValue("Cookie", in: headers)
        let resolvedCookieHeader: String? = self.resolvedCookieHeader(
            cookiePolicy: cookiePolicy,
            cookiePriority: cookiePriority,
            customCookieHeader: customCookieHeader,
            browserCookieHeader: browserCookieHeader,
            credentialCookieHeader: credentialCookieHeader
        )

        self.removeHeader("Cookie", from: &resolvedHeaders)

        if let resolvedCookieHeader: String = resolvedCookieHeader,
           resolvedCookieHeader.isEmpty == false {
            resolvedHeaders["Cookie"] = resolvedCookieHeader
        }

        return resolvedHeaders
    }

    static func resolvedCookieHeader(
        cookiePolicy: CookiePolicy?,
        cookiePriority: CookiePriority?,
        customCookieHeader: String?,
        browserCookieHeader: String?
    ) -> String? {
        return self.resolvedCookieHeader(
            cookiePolicy: cookiePolicy,
            cookiePriority: cookiePriority,
            customCookieHeader: customCookieHeader,
            browserCookieHeader: browserCookieHeader,
            credentialCookieHeader: nil
        )
    }

    static func resolvedCookieHeader(
        cookiePolicy: CookiePolicy?,
        cookiePriority: CookiePriority?,
        customCookieHeader: String?,
        browserCookieHeader: String?,
        credentialCookieHeader: String?
    ) -> String? {
        let browserLikeCookieHeader: String? = self.mergedCookieHeader(
            primaryCookieHeader: credentialCookieHeader,
            secondaryCookieHeader: browserCookieHeader
        )

        switch cookiePolicy {
        case .some(.none):
            return nil
        case .some(.custom):
            return customCookieHeader
        case .some(.browser):
            return browserLikeCookieHeader
        case .some(.browserThenCustom):
            return self.mergedCookieHeader(
                customCookieHeader: customCookieHeader,
                browserCookieHeader: browserLikeCookieHeader,
                cookiePriority: cookiePriority
            )
        case nil:
            return customCookieHeader
        }
    }

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

    private static func mergedCookieHeader(
        primaryCookieHeader: String?,
        secondaryCookieHeader: String?
    ) -> String? {
        let primaryCookies: [(name: String, value: String)] = self.cookiePairs(from: primaryCookieHeader)
        let secondaryCookies: [(name: String, value: String)] = self.cookiePairs(from: secondaryCookieHeader)

        if primaryCookies.isEmpty {
            return secondaryCookieHeader
        }

        if secondaryCookies.isEmpty {
            return primaryCookieHeader
        }

        return self.mergeCookiePairs(primary: primaryCookies, secondary: secondaryCookies)
            .map { pair in "\(pair.name)=\(pair.value)" }
            .joined(separator: "; ")
    }

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
