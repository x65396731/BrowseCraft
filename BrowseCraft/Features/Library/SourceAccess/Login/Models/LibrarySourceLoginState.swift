import BrowseCraftCore
import Foundation

enum LibrarySourceLoginStatus: Hashable {
    case guest
    case authenticated
}

struct LibrarySourceLoginState: Hashable, Identifiable {
    let sourceID: String
    let sourceName: String
    let baseURL: URL
    let loginURL: URL
    let credentialKeys: [String]
    let status: LibrarySourceLoginStatus

    var id: String {
        return "\(self.sourceID)|\(self.loginURL.absoluteString)"
    }
}

// 中文注释：L1 仅解析当前 Source 是否声明登录入口及已有凭据状态；WebUI 登录行为由 L2 接入。
struct LibrarySourceLoginStateResolver {
    let credentialStore: SourceCredentialStoring
    let now: () -> Date

    init(
        credentialStore: SourceCredentialStoring,
        now: @escaping () -> Date = Date.init
    ) {
        self.credentialStore = credentialStore
        self.now = now
    }

    func resolve(source: Source?) -> LibrarySourceLoginState? {
        guard let source: Source,
              let loginURL: URL = self.loginURL(for: source),
              let baseURL: URL = URL(string: source.baseURL) else {
            return nil
        }

        return LibrarySourceLoginState(
            sourceID: source.id,
            sourceName: source.name,
            baseURL: baseURL,
            loginURL: loginURL,
            credentialKeys: self.credentialKeys(for: source),
            status: self.hasActiveCredential(for: source.id) ? .authenticated : .guest
        )
    }

    private func loginURL(for source: Source) -> URL? {
        guard case .comic(let configuration) = source.configuration,
              let rawLoginURL: String = configuration.rule.site?.loginURL else {
            return nil
        }

        let loginURLString: String = rawLoginURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard loginURLString.isEmpty == false,
              let loginURL: URL = URL(string: loginURLString),
              let scheme: String = loginURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        return loginURL
    }

    private func credentialKeys(for source: Source) -> [String] {
        guard case .comic(let configuration) = source.configuration,
              let context: [String: SiteRuleContextValue] = configuration.rule.context else {
            return []
        }

        let keys: Set<String> = Set(context.values.compactMap { value in
            return value.userValue.flatMap(self.credentialKey(from:))
        })
        return keys.sorted()
    }

    private func credentialKey(from template: String) -> String? {
        var value: String = template.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("{") && value.hasSuffix("}") {
            value.removeFirst()
            value.removeLast()
        }

        let prefix: String = "credentialStore."
        guard value.hasPrefix(prefix) else {
            return nil
        }

        let key: String = String(value.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.isEmpty == false,
              key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else {
            return nil
        }
        return key
    }

    private func hasActiveCredential(for sourceID: String) -> Bool {
        guard let credential: SourceCredential = self.credentialStore.credential(sourceID: sourceID),
              credential.expiresAt.map({ $0 > self.now() }) ?? true else {
            return false
        }

        let now: Date = self.now()
        let hasActiveCookie: Bool = credential.cookies.contains { cookie in
            return cookie.expiresDate.map({ $0 > now }) ?? true
        }

        return hasActiveCookie
            || credential.headers.isEmpty == false
            || credential.accessToken?.isEmpty == false
            || credential.refreshToken?.isEmpty == false
            || credential.localStorage.isEmpty == false
            || credential.sessionStorage.isEmpty == false
    }
}
