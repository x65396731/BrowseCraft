import Foundation

public protocol SystemCookieHeaderProviding: Sendable {
    func cookieHeader(for url: URL) -> String?
}

public struct EmptySystemCookieHeaderProvider: SystemCookieHeaderProviding, Sendable {
    public init() {}

    public func cookieHeader(for url: URL) -> String? {
        return nil
    }
}
