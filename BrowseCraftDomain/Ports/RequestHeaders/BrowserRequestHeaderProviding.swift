import Foundation

public protocol BrowserRequestHeaderProviding: Sendable {
    var userAgent: String { get }

    func defaultHeaders(
        for url: URL,
        referer: URL?,
        includeOrigin: Bool
    ) -> [String: String]
}

public extension BrowserRequestHeaderProviding {
    func defaultHeaders(for url: URL) -> [String: String] {
        return self.defaultHeaders(for: url, referer: nil, includeOrigin: false)
    }

    func playbackHeaders(referer: URL) -> [String: String] {
        return self.defaultHeaders(for: referer, referer: referer, includeOrigin: true)
    }
}

public struct EmptyBrowserRequestHeaderProvider: BrowserRequestHeaderProviding, Sendable {
    public init() {}

    public let userAgent: String = ""

    public func defaultHeaders(
        for url: URL,
        referer: URL?,
        includeOrigin: Bool
    ) -> [String: String] {
        return [:]
    }
}
