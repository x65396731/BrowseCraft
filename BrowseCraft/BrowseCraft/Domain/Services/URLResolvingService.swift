import Foundation

enum URLResolvingError: LocalizedError {
    case invalidURL(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let rawURL):
            return "Invalid URL: \(rawURL)"
        }
    }
}

/// Small URL helper kept out of SwiftUI and out of the parser.
///
/// Site rules often contain relative URLs. This service centralizes how we turn
/// them into absolute URLs.
struct URLResolvingService {
    func listURL(for source: Source, page: Int) throws -> URL {
        let rawURL: String = source.rule.list.url.replacingOccurrences(of: "{page}", with: String(page))
        let absoluteURLString: String = self.absoluteString(rawURL, baseURLString: source.baseURL)

        guard let url: URL = URL(string: absoluteURLString) else {
            throw URLResolvingError.invalidURL(rawURL)
        }

        return url
    }

    func absoluteString(_ rawURLString: String, baseURLString: String) -> String {
        if let url: URL = URL(string: rawURLString), url.scheme != nil {
            return rawURLString
        }

        guard let baseURL: URL = URL(string: baseURLString) else {
            return rawURLString
        }

        guard let resolvedURL: URL = URL(string: rawURLString, relativeTo: baseURL) else {
            return rawURLString
        }

        return resolvedURL.absoluteURL.absoluteString
    }
}

