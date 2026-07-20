import Foundation

protocol SystemCookieHeaderProviding: Sendable {
    func cookieHeader(for url: URL) -> String?
}

struct EmptySystemCookieHeaderProvider: SystemCookieHeaderProviding {
    func cookieHeader(for url: URL) -> String? {
        return nil
    }
}
