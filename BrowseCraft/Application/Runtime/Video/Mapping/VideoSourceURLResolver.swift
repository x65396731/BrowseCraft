import Foundation
import BrowseCraftCore

// 中文注释：VideoSourceURLResolver 只把用户输入的 video URL 归一化；不判断站点 adapter/类型。
struct VideoSourceURLResolver {
    func resolve(_ input: String) throws -> VideoSourceURLResolution {
        let url: URL = try self.normalizedURL(from: input)
        try self.rejectRSSURL(url)

        let baseURL: URL = self.baseURL(from: url)
        let path: String = self.normalizedPath(url.path)

        if path == "/" {
            return VideoSourceURLResolution(
                baseURL: baseURL,
                entryURL: baseURL,
                seedURL: nil,
                entryKind: .home,
                normalizedEntryURL: baseURL,
                vodID: nil,
                sourceIndex: nil,
                episodeIndex: nil,
                defaultListURL: baseURL,
                seedDetailURL: nil,
                seedPlayURL: nil
            )
        }

        if self.matches(path, pattern: #"^/vodtype/\d+\.html$"#)
            || self.matches(path, pattern: #"^/vodshow/.+\.html$"#) {
            let entryKind: VideoSourceEntryKind = path.hasPrefix("/vodtype/") ? .category : .list
            return VideoSourceURLResolution(
                baseURL: baseURL,
                entryURL: url,
                seedURL: nil,
                entryKind: entryKind,
                normalizedEntryURL: url,
                vodID: nil,
                sourceIndex: nil,
                episodeIndex: nil,
                defaultListURL: url,
                seedDetailURL: nil,
                seedPlayURL: nil
            )
        }

        if let vodID: String = self.firstMatch(path, pattern: #"^/voddetail/(\d+)\.html$"#) {
            return VideoSourceURLResolution(
                baseURL: baseURL,
                entryURL: baseURL,
                seedURL: url,
                entryKind: .detail,
                normalizedEntryURL: baseURL,
                vodID: vodID,
                sourceIndex: nil,
                episodeIndex: nil,
                defaultListURL: baseURL,
                seedDetailURL: url,
                seedPlayURL: nil
            )
        }

        if let match: VideoPlayRoute = self.playRoute(from: path) {
            let detailURL: URL? = self.url(path: "/voddetail/\(match.vodID).html", baseURL: baseURL)
            return VideoSourceURLResolution(
                baseURL: baseURL,
                entryURL: baseURL,
                seedURL: url,
                entryKind: .play,
                normalizedEntryURL: baseURL,
                vodID: match.vodID,
                sourceIndex: match.sourceIndex,
                episodeIndex: match.episodeIndex,
                defaultListURL: baseURL,
                seedDetailURL: detailURL,
                seedPlayURL: url
            )
        }

        return VideoSourceURLResolution(
            baseURL: baseURL,
            entryURL: url,
            seedURL: nil,
            entryKind: .home,
            normalizedEntryURL: url,
            vodID: nil,
            sourceIndex: nil,
            episodeIndex: nil,
            defaultListURL: url,
            seedDetailURL: nil,
            seedPlayURL: nil
        )
    }

    private func normalizedURL(from input: String) throws -> URL {
        let trimmed: String = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              var components: URLComponents = URLComponents(string: trimmed),
              let scheme: String = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host?.isEmpty == false else {
            throw VideoSourceURLResolverError.invalidURL
        }

        if scheme == "http" {
            components.scheme = "https"
        }

        components.fragment = nil

        guard let url: URL = components.url else {
            throw VideoSourceURLResolverError.invalidURL
        }

        return url
    }

    private func rejectRSSURL(_ url: URL) throws {
        let lowercasedPath: String = url.path.lowercased()
        if lowercasedPath.hasSuffix(".xml")
            || lowercasedPath.hasSuffix(".rss")
            || lowercasedPath.contains("/rss") {
            throw VideoSourceURLResolverError.rssURLNotVideo
        }
    }

    private func baseURL(from url: URL) -> URL {
        var components: URLComponents = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = "/"
        return components.url ?? url
    }

    private func normalizedPath(_ path: String) -> String {
        if path.isEmpty {
            return "/"
        }

        return path.hasPrefix("/") ? path : "/\(path)"
    }

    private func playRoute(from path: String) -> VideoPlayRoute? {
        guard let result: NSTextCheckingResult = self.match(
            path,
            pattern: #"^/vodplay/(\d+)-(\d+)-(\d+)\.html$"#
        ) else {
            return nil
        }

        guard let vodID: String = self.substring(path, range: result.range(at: 1)),
              let sourceIndexString: String = self.substring(path, range: result.range(at: 2)),
              let episodeIndexString: String = self.substring(path, range: result.range(at: 3)),
              let sourceIndex: Int = Int(sourceIndexString),
              let episodeIndex: Int = Int(episodeIndexString) else {
            return nil
        }

        return VideoPlayRoute(
            vodID: vodID,
            sourceIndex: sourceIndex,
            episodeIndex: episodeIndex
        )
    }

    private func url(path: String, baseURL: URL) -> URL? {
        return URL(string: path, relativeTo: baseURL)?.absoluteURL
    }

    private func matches(_ string: String, pattern: String) -> Bool {
        return self.match(string, pattern: pattern) != nil
    }

    private func firstMatch(_ string: String, pattern: String) -> String? {
        guard let result: NSTextCheckingResult = self.match(string, pattern: pattern) else {
            return nil
        }

        return self.substring(string, range: result.range(at: 1))
    }

    private func match(_ string: String, pattern: String) -> NSTextCheckingResult? {
        guard let regex: NSRegularExpression = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range: NSRange = NSRange(string.startIndex..<string.endIndex, in: string)
        return regex.firstMatch(in: string, range: range)
    }

    private func substring(_ string: String, range: NSRange) -> String? {
        guard range.location != NSNotFound,
              let swiftRange: Range<String.Index> = Range(range, in: string) else {
            return nil
        }

        return String(string[swiftRange])
    }
}

struct VideoSourceURLResolution: Hashable {
    var baseURL: URL
    var entryURL: URL
    var seedURL: URL?
    var entryKind: VideoSourceEntryKind
    var normalizedEntryURL: URL
    var vodID: String?
    var sourceIndex: Int?
    var episodeIndex: Int?
    var defaultListURL: URL?
    var seedDetailURL: URL?
    var seedPlayURL: URL?
}

private struct VideoPlayRoute {
    var vodID: String
    var sourceIndex: Int
    var episodeIndex: Int
}

enum VideoSourceURLResolverError: LocalizedError, Equatable {
    case invalidURL
    case rssURLNotVideo
    case unsupportedVideoURL

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Enter a valid http or https video site URL."
        case .rssURLNotVideo:
            return "This URL looks like an RSS feed. Add it from RSS Feed instead."
        case .unsupportedVideoURL:
            return "This video URL cannot be inspected right now."
        }
    }
}
