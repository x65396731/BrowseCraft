import Foundation

// 中文注释：站点登录态的内存实现，保留现有凭证匹配、Cookie 生成和调试行为。
final class InMemorySourceCredentialStore: SourceCredentialStoring {
    private let lock: NSLock = NSLock()
    private var credentialsBySourceID: [String: SourceCredential] = [:]

    func save(_ credential: SourceCredential) {
        self.lock.lock()
        defer { self.lock.unlock() }

        self.credentialsBySourceID[credential.sourceID] = credential

        AppLog.debug(
            .credential,
            event: "saved",
            metadata: [
                "sourceID": credential.sourceID,
                "hasBaseURL": (credential.baseURL != nil).description,
                "cookieCount": String(credential.cookies.count),
                "headerCount": String(credential.headers.count),
                "hasAccessToken": (credential.accessToken != nil).description,
                "localStorageCount": String(credential.localStorage.count),
                "sessionStorageCount": String(credential.sessionStorage.count),
                "origin": credential.origin.rawValue
            ]
        )
    }

    func removeCredential(sourceID: String) {
        self.lock.lock()
        defer { self.lock.unlock() }

        let removedCredential: SourceCredential? = self.credentialsBySourceID.removeValue(forKey: sourceID)

        AppLog.debug(
            .credential,
            event: "removed",
            metadata: [
                "sourceID": sourceID,
                "removed": (removedCredential != nil).description
            ]
        )
    }

    func credential(sourceID: String) -> SourceCredential? {
        self.lock.lock()
        defer { self.lock.unlock() }

        return self.credentialsBySourceID[sourceID]
    }

    func cookieHeader(for context: SourceRequestContext, url: URL) -> String? {
        guard let credential: SourceCredential = self.cookieCredential(for: context),
              credential.cookies.isEmpty == false else {
            #if DEBUG
            self.debugCredentialMiss(context: context, url: url, operation: "cookie")
            #endif
            return nil
        }

        let matchingCookies: [HTTPCookie] = credential.cookies.filter { cookie in
            return self.cookie(cookie, matches: url)
        }

        guard matchingCookies.isEmpty == false else {
            AppLog.debug(
                .credential,
                event: "cookie-miss",
                metadata: self.metadata(context: context, url: url).merging(
                    ["reason": "noMatchingCookie"],
                    uniquingKeysWith: { _, new in new }
                )
            )
            return nil
        }

        AppLog.debug(
            .credential,
            event: "cookie-hit",
            metadata: self.metadata(context: context, url: url).merging(
                ["matchedCookieCount": String(matchingCookies.count)],
                uniquingKeysWith: { _, new in new }
            )
        )

        return HTTPCookie
            .requestHeaderFields(with: matchingCookies)["Cookie"]
    }

    func headerOverrides(for context: SourceRequestContext, url: URL) -> [String: String] {
        guard let credential: SourceCredential = self.headerCredential(for: context, url: url),
              self.isExpired(credential) == false else {
            #if DEBUG
            self.debugCredentialMiss(context: context, url: url, operation: "headers")
            #endif
            return [:]
        }

        let headers: [String: String] = credential.headers.filter { key, _ in
            return key.caseInsensitiveCompare("Cookie") != .orderedSame
        }

        AppLog.debug(
            .credential,
            event: "headers-hit",
            metadata: self.metadata(context: context, url: url).merging(
                ["headerCount": String(headers.count)],
                uniquingKeysWith: { _, new in new }
            )
        )

        return headers
    }

    func token(for sourceID: String, key: String) -> String? {
        guard let credential: SourceCredential = self.credential(sourceID: sourceID),
              self.isExpired(credential) == false else {
            AppLog.debug(
                .credential,
                event: "token-miss",
                metadata: ["sourceID": sourceID]
            )
            return nil
        }

        let value: String?
        switch key {
        case "accessToken":
            value = credential.accessToken
        case "refreshToken":
            value = credential.refreshToken
        default:
            value = nil
        }

        AppLog.debug(
            .credential,
            event: "token-lookup",
            metadata: [
                "sourceID": sourceID,
                "hit": (value != nil).description
            ]
        )

        return value
    }

    func storageValue(for sourceID: String, storage: SourceCredentialStorage, key: String) -> String? {
        guard let credential: SourceCredential = self.credential(sourceID: sourceID),
              self.isExpired(credential) == false else {
            AppLog.debug(
                .credential,
                event: "storage-miss",
                metadata: [
                    "sourceID": sourceID,
                    "storage": storage.rawValue
                ]
            )
            return nil
        }

        let value: String?
        switch storage {
        case .localStorage:
            value = credential.localStorage[key]
        case .sessionStorage:
            value = credential.sessionStorage[key]
        }

        AppLog.debug(
            .credential,
            event: "storage-lookup",
            metadata: [
                "sourceID": sourceID,
                "storage": storage.rawValue,
                "hit": (value != nil).description
            ]
        )

        return value
    }

    /// 中文注释：Cookie 是否可发送由 Cookie 自身的 Domain/Path/Secure 等属性决定，不能被 source baseURL 的单一 host 预先拦截。
    private func cookieCredential(for context: SourceRequestContext) -> SourceCredential? {
        guard let sourceID: String = context.sourceID,
              let credential: SourceCredential = self.credential(sourceID: sourceID),
              self.isExpired(credential) == false else {
            return nil
        }

        return credential
    }

    /// 中文注释：自定义 Header 仍限制在凭据 baseURL host 及其子域，避免因 Cookie 的跨子域能力扩大 Header 泄露范围。
    private func headerCredential(for context: SourceRequestContext, url: URL) -> SourceCredential? {
        guard let sourceID: String = context.sourceID,
              let credential: SourceCredential = self.credential(sourceID: sourceID),
              self.isExpired(credential) == false,
              self.matchesBaseURL(credential.baseURL ?? context.baseURL, url: url) else {
            return nil
        }

        return credential
    }

    private func isExpired(_ credential: SourceCredential) -> Bool {
        guard let expiresAt: Date = credential.expiresAt else {
            return false
        }

        return expiresAt <= Date()
    }

    private func matchesBaseURL(_ baseURL: URL?, url: URL) -> Bool {
        guard let baseURL: URL else {
            return true
        }

        guard let baseHost: String = baseURL.host?.lowercased(),
              let requestHost: String = url.host?.lowercased() else {
            return false
        }

        return requestHost == baseHost || requestHost.hasSuffix(".\(baseHost)")
    }

    private func cookie(_ cookie: HTTPCookie, matches url: URL) -> Bool {
        if let expiresDate: Date = cookie.expiresDate,
           expiresDate <= Date() {
            return false
        }

        guard let host: String = url.host?.lowercased() else {
            return false
        }

        if cookie.isSecure,
           url.scheme?.lowercased() != "https" {
            return false
        }

        let cookieDomain: String = cookie.domain
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        let hostMatches: Bool = host == cookieDomain || host.hasSuffix(".\(cookieDomain)")
        let requestPath: String = url.path.isEmpty ? "/" : url.path
        let pathMatches: Bool = requestPath.hasPrefix(cookie.path)

        return hostMatches && pathMatches
    }

    #if DEBUG
    private func debugCredentialMiss(
        context: SourceRequestContext,
        url: URL,
        operation: String
    ) {
        AppLog.debug(
            .credential,
            event: "\(operation)-miss",
            metadata: self.metadata(context: context, url: url)
        )
    }
    #endif

    private func metadata(
        context: SourceRequestContext,
        url: URL
    ) -> [String: String] {
        return [
            "sourceID": context.sourceID ?? "nil",
            "purpose": context.purpose.rawValue,
            "host": url.host ?? "nil"
        ]
    }
}
