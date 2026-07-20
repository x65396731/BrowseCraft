import Foundation
import WebKit

enum SourceLoginSessionDomainMatcher {
    static func matches(cookie: HTTPCookie, state: LibrarySourceLoginState) -> Bool {
        let cookieDomain: String = cookie.domain
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        return self.hosts(for: state).contains { host in
            return host == cookieDomain || host.hasSuffix(".\(cookieDomain)")
        }
    }

    static func matches(record: WKWebsiteDataRecord, state: LibrarySourceLoginState) -> Bool {
        let recordDomain: String = record.displayName
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        return self.hosts(for: state).contains { host in
            return host == recordDomain
                || host.hasSuffix(".\(recordDomain)")
                || recordDomain.hasSuffix(".\(host)")
        }
    }

    private static func hosts(for state: LibrarySourceLoginState) -> [String] {
        return [state.baseURL.host, state.loginURL.host]
            .compactMap { $0?.lowercased() }
    }
}
