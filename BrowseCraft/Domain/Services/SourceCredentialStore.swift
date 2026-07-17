import Foundation

// 中文注释：SourceCredentialStore.swift 是站点登录态抽象的第一段实现，只提供运行时凭证合并能力，不提供登录 UI。

enum SourceCredentialOrigin: String {
    case webView
    case manual
    case apiLogin
    case importedCookie
    case memory
}

enum SourceCredentialStorage: String {
    case localStorage
    case sessionStorage
}

struct SourceCredential {
    let sourceID: String
    let baseURL: URL?
    let cookies: [HTTPCookie]
    let headers: [String: String]
    let accessToken: String?
    let refreshToken: String?
    let localStorage: [String: String]
    let sessionStorage: [String: String]
    let expiresAt: Date?
    let origin: SourceCredentialOrigin

    init(
        sourceID: String,
        baseURL: URL? = nil,
        cookies: [HTTPCookie] = [],
        headers: [String: String] = [:],
        accessToken: String? = nil,
        refreshToken: String? = nil,
        localStorage: [String: String] = [:],
        sessionStorage: [String: String] = [:],
        expiresAt: Date? = nil,
        origin: SourceCredentialOrigin = .memory
    ) {
        self.sourceID = sourceID
        self.baseURL = baseURL
        self.cookies = cookies
        self.headers = headers
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.localStorage = localStorage
        self.sessionStorage = sessionStorage
        self.expiresAt = expiresAt
        self.origin = origin
    }
}

protocol SourceCredentialProviding {
    func cookieHeader(for context: SourceRequestContext, url: URL) -> String?
    func headerOverrides(for context: SourceRequestContext, url: URL) -> [String: String]
    func token(for sourceID: String, key: String) -> String?
    func storageValue(for sourceID: String, storage: SourceCredentialStorage, key: String) -> String?
}

protocol SourceCredentialStoring: SourceCredentialProviding {
    func save(_ credential: SourceCredential)
    func removeCredential(sourceID: String)
    func credential(sourceID: String) -> SourceCredential?
}

struct EmptySourceCredentialProvider: SourceCredentialProviding {
    func cookieHeader(for context: SourceRequestContext, url: URL) -> String? {
        return nil
    }

    func headerOverrides(for context: SourceRequestContext, url: URL) -> [String: String] {
        return [:]
    }

    func token(for sourceID: String, key: String) -> String? {
        return nil
    }

    func storageValue(for sourceID: String, storage: SourceCredentialStorage, key: String) -> String? {
        return nil
    }
}

final class InMemorySourceCredentialStore: SourceCredentialStoring {
    private let lock: NSLock = NSLock()
    private var credentialsBySourceID: [String: SourceCredential] = [:]

    func save(_ credential: SourceCredential) {
        self.lock.lock()
        defer { self.lock.unlock() }

        self.credentialsBySourceID[credential.sourceID] = credential

        #if DEBUG
        print(
            "[BrowseCraftCredential] save " +
            "sourceID=\(credential.sourceID) " +
            "hasBaseURL=\((credential.baseURL != nil).description) " +
            "cookieCount=\(credential.cookies.count) " +
            "headerCount=\(credential.headers.count) " +
            "hasAccessToken=\((credential.accessToken != nil).description) " +
            "localStorageCount=\(credential.localStorage.count) " +
            "sessionStorageCount=\(credential.sessionStorage.count) " +
            "origin=\(credential.origin.rawValue)"
        )
        #endif
    }

    func removeCredential(sourceID: String) {
        self.lock.lock()
        defer { self.lock.unlock() }

        let removedCredential: SourceCredential? = self.credentialsBySourceID.removeValue(forKey: sourceID)

        #if DEBUG
        print(
            "[BrowseCraftCredential] remove " +
            "sourceID=\(sourceID) " +
            "removed=\((removedCredential != nil).description)"
        )
        #endif
    }

    func credential(sourceID: String) -> SourceCredential? {
        self.lock.lock()
        defer { self.lock.unlock() }

        return self.credentialsBySourceID[sourceID]
    }

    func cookieHeader(for context: SourceRequestContext, url: URL) -> String? {
        guard let credential: SourceCredential = self.credential(for: context, url: url),
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
            #if DEBUG
            print(
                "[BrowseCraftCredential] cookie miss " +
                "sourceID=\(context.sourceID ?? "nil") " +
                "purpose=\(context.purpose.rawValue) " +
                "host=\(url.host ?? "nil") " +
                "reason=noMatchingCookie"
            )
            #endif
            return nil
        }

        #if DEBUG
        print(
            "[BrowseCraftCredential] cookie hit " +
            "sourceID=\(credential.sourceID) " +
            "purpose=\(context.purpose.rawValue) " +
            "host=\(url.host ?? "nil") " +
            "matchedCookieCount=\(matchingCookies.count)"
        )
        #endif

        return HTTPCookie
            .requestHeaderFields(with: matchingCookies)["Cookie"]
    }

    func headerOverrides(for context: SourceRequestContext, url: URL) -> [String: String] {
        guard let credential: SourceCredential = self.credential(for: context, url: url),
              self.isExpired(credential) == false else {
            #if DEBUG
            self.debugCredentialMiss(context: context, url: url, operation: "headers")
            #endif
            return [:]
        }

        let headers: [String: String] = credential.headers.filter { key, _ in
            return key.caseInsensitiveCompare("Cookie") != .orderedSame
        }

        #if DEBUG
        print(
            "[BrowseCraftCredential] headers hit " +
            "sourceID=\(credential.sourceID) " +
            "purpose=\(context.purpose.rawValue) " +
            "host=\(url.host ?? "nil") " +
            "headerCount=\(headers.count)"
        )
        #endif

        return headers
    }

    func token(for sourceID: String, key: String) -> String? {
        guard let credential: SourceCredential = self.credential(sourceID: sourceID),
              self.isExpired(credential) == false else {
            #if DEBUG
            print(
                "[BrowseCraftCredential] token miss " +
                "sourceID=\(sourceID) " +
                "key=\(key)"
            )
            #endif
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

        #if DEBUG
        print(
            "[BrowseCraftCredential] token lookup " +
            "sourceID=\(sourceID) " +
            "key=\(key) " +
            "hit=\((value != nil).description)"
        )
        #endif

        return value
    }

    func storageValue(for sourceID: String, storage: SourceCredentialStorage, key: String) -> String? {
        guard let credential: SourceCredential = self.credential(sourceID: sourceID),
              self.isExpired(credential) == false else {
            #if DEBUG
            print(
                "[BrowseCraftCredential] storage miss " +
                "sourceID=\(sourceID) " +
                "storage=\(storage.rawValue) " +
                "key=\(key)"
            )
            #endif
            return nil
        }

        let value: String?
        switch storage {
        case .localStorage:
            value = credential.localStorage[key]
        case .sessionStorage:
            value = credential.sessionStorage[key]
        }

        #if DEBUG
        print(
            "[BrowseCraftCredential] storage lookup " +
            "sourceID=\(sourceID) " +
            "storage=\(storage.rawValue) " +
            "key=\(key) " +
            "hit=\((value != nil).description)"
        )
        #endif

        return value
    }

    private func credential(for context: SourceRequestContext, url: URL) -> SourceCredential? {
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
        guard let host: String = url.host?.lowercased() else {
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
        print(
            "[BrowseCraftCredential] \(operation) miss " +
            "sourceID=\(context.sourceID ?? "nil") " +
            "purpose=\(context.purpose.rawValue) " +
            "host=\(url.host ?? "nil")"
        )
    }
    #endif
}
