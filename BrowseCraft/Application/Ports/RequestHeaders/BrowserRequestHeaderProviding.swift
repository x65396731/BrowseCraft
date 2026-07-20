import Foundation

protocol BrowserRequestHeaderProviding: Sendable {
    var userAgent: String { get }

    func defaultHeaders(
        for url: URL,
        referer: URL?,
        includeOrigin: Bool
    ) -> [String: String]
}

extension BrowserRequestHeaderProviding {
    func defaultHeaders(for url: URL) -> [String: String] {
        return self.defaultHeaders(for: url, referer: nil, includeOrigin: false)
    }

    func playbackHeaders(referer: URL) -> [String: String] {
        return self.defaultHeaders(for: referer, referer: referer, includeOrigin: true)
    }
}

struct EmptyBrowserRequestHeaderProvider: BrowserRequestHeaderProviding {
    let userAgent: String = ""

    func defaultHeaders(
        for url: URL,
        referer: URL?,
        includeOrigin: Bool
    ) -> [String: String] {
        return [:]
    }
}
