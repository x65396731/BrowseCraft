import Foundation
import SwiftSoup

struct DiscoverRSSFeedsInput {
    let siteURLString: String
}

enum DiscoverRSSFeedsError: LocalizedError, Equatable {
    case invalidURL
    case nonFeedResponse(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Enter a valid http or https URL."
        case .nonFeedResponse(let preview):
            return "The candidate returned a non-RSS page: \(preview)"
        }
    }
}

struct DiscoverRSSFeedsUseCase {
    private let pageContentLoader: PageContentLoader
    private let rssFeedLoader: any RSSFeedLoading
    private let urlResolver: URLResolvingService
    private let maxCandidates: Int

    init(
        pageContentLoader: PageContentLoader,
        rssFeedLoader: any RSSFeedLoading,
        urlResolver: URLResolvingService,
        maxCandidates: Int = 24
    ) {
        self.pageContentLoader = pageContentLoader
        self.rssFeedLoader = rssFeedLoader
        self.urlResolver = urlResolver
        self.maxCandidates = maxCandidates
    }

    func execute(_ input: DiscoverRSSFeedsInput) async throws -> [DiscoveredRSSFeedItem] {
        let siteURL: URL = try self.siteURL(from: input.siteURLString)
        var candidates: [URL] = []

        for discoveryURL in self.discoveryEntryURLs(for: siteURL) {
            self.appendCandidate(discoveryURL, to: &candidates)

            do {
                let html: String = try await self.pageContentLoader.getString(from: discoveryURL, request: nil)
                for candidate in try self.feedURLs(from: html, siteURL: discoveryURL) {
                    self.appendCandidate(candidate, to: &candidates)
                }
            } catch {
                #if DEBUG
                print(
                    "[BrowseCraftRSSDiscovery] html-load-failed " +
                    "site=\(discoveryURL.absoluteString) error=\(error)"
                )
                #endif
            }

            for candidate in self.commonFeedURLs(for: discoveryURL) {
                self.appendCandidate(candidate, to: &candidates)
            }
        }

        #if DEBUG
        print(
            "[BrowseCraftRSSDiscovery] start site=\(siteURL.absoluteString) " +
            "candidateCount=\(candidates.count)"
        )
        #endif

        var results: [DiscoveredRSSFeedItem] = []
        for candidate in candidates.prefix(self.maxCandidates) {
            do {
                let feed: RSSFeed = try await self.loadFeedCandidate(candidate)
                guard feed.items.isEmpty == false else {
                    self.logRejected(candidate, reason: "empty-feed")
                    continue
                }

                let title: String = feed.title?.trimmedNonEmpty
                    ?? candidate.host
                    ?? "RSS Feed"
                results.append(
                    DiscoveredRSSFeedItem(
                        feedURL: candidate,
                        siteURL: siteURL,
                        title: title,
                        itemCount: feed.items.count,
                        firstItemTitle: feed.items.first?.title?.trimmedNonEmpty
                    )
                )
                self.logAccepted(candidate, title: title, count: feed.items.count)
            } catch {
                self.logRejected(candidate, reason: error.localizedDescription)
            }
        }

        return results
    }

    private func discoveryEntryURLs(for siteURL: URL) -> [URL] {
        var urls: [URL] = [siteURL]

        if let desktopURL: URL = self.desktopURLIfMobileHost(siteURL) {
            urls.append(desktopURL)
        }

        return urls
    }

    private func desktopURLIfMobileHost(_ url: URL) -> URL? {
        guard let host: String = url.host?.lowercased(),
              host.hasPrefix("m.") || host.hasPrefix("wap."),
              var components: URLComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let trimmedHost: String
        if host.hasPrefix("wap.") {
            trimmedHost = String(host.dropFirst(4))
        } else {
            trimmedHost = String(host.dropFirst(2))
        }

        components.host = trimmedHost
        components.path = "/"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private func loadFeedCandidate(_ candidate: URL) async throws -> RSSFeed {
        if let dataLoader: PageDataLoader = self.pageContentLoader as? PageDataLoader {
            let data: Data = try await dataLoader.getData(from: candidate, request: nil)
            let preview: String = Self.textPreview(from: data)
            guard Self.looksLikeFeedDocument(preview) else {
                throw DiscoverRSSFeedsError.nonFeedResponse(Self.nonFeedPreview(from: preview))
            }

            return try RSSFeedMapper().map(data)
        }

        let xml: String = try await self.pageContentLoader.getString(from: candidate, request: nil)
        guard Self.looksLikeFeedDocument(xml) else {
            throw DiscoverRSSFeedsError.nonFeedResponse(Self.nonFeedPreview(from: xml))
        }

        return try RSSFeedMapper().map(xml)
    }

    private func siteURL(from string: String) throws -> URL {
        let trimmed: String = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components: URLComponents = URLComponents(string: trimmed) else {
            throw DiscoverRSSFeedsError.invalidURL
        }

        if components.scheme == nil {
            components.scheme = "https"
        }

        guard let url: URL = components.url,
              let scheme: String = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else {
            throw DiscoverRSSFeedsError.invalidURL
        }

        return url
    }

    private func feedURLs(from html: String, siteURL: URL) throws -> [URL] {
        let document: Document = try SwiftSoup.parse(html, siteURL.absoluteString)
        let selectors: [String] = [
            "link[rel~=alternate][type*=rss]",
            "link[rel~=alternate][type*=atom]",
            "a[href*=rss]",
            "a[href*=feed]",
            "a[href*=atom]"
        ]
        var urls: [URL] = []

        for selector in selectors {
            let elements: Elements = try document.select(selector)
            for element in elements.array() {
                let rawHref: String = try element.attr("href").trimmingCharacters(in: .whitespacesAndNewlines)
                guard rawHref.isEmpty == false else {
                    continue
                }

                let absoluteString: String = self.urlResolver.absoluteString(
                    rawHref,
                    baseURLString: siteURL.absoluteString
                )
                guard let url: URL = URL(string: absoluteString),
                      self.shouldKeepCandidate(url),
                      self.shouldKeepHTMLCandidate(url, selector: selector, siteURL: siteURL) else {
                    continue
                }

                urls.append(url)
            }
        }

        return urls
    }

    private func commonFeedURLs(for siteURL: URL) -> [URL] {
        let feedNames: [String] = [
            "feed",
            "rss",
            "rss.xml",
            "atom.xml",
            "feed.xml",
            "index.xml"
        ]

        var paths: [String] = []
        for basePath in self.feedBasePaths(for: siteURL) {
            for feedName in feedNames {
                paths.append(self.joinPath(basePath, feedName))
            }
        }

        var urls: [URL] = paths.compactMap { path in
            var components: URLComponents? = URLComponents(url: siteURL, resolvingAgainstBaseURL: false)
            components?.path = path
            components?.query = nil
            components?.fragment = nil
            return components?.url
        }

        if let googleNewsRSSURL: URL = self.googleNewsRSSURLPreservingLocale(from: siteURL) {
            urls.insert(googleNewsRSSURL, at: 0)
        }

        return urls
    }

    private func feedBasePaths(for siteURL: URL) -> [String] {
        let trimmedPath: String = siteURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard trimmedPath.isEmpty == false else {
            return ["/"]
        }

        let parts: [String] = trimmedPath.split(separator: "/").map(String.init)
        var paths: [String] = ["/"]

        for length in stride(from: parts.count, through: 1, by: -1) {
            paths.append("/" + parts.prefix(length).joined(separator: "/"))
        }

        return paths
    }

    private func joinPath(_ basePath: String, _ feedName: String) -> String {
        if basePath == "/" {
            return "/" + feedName
        }

        return basePath + "/" + feedName
    }

    private func googleNewsRSSURLPreservingLocale(from siteURL: URL) -> URL? {
        guard siteURL.host?.lowercased() == "news.google.com",
              let query: String = URLComponents(url: siteURL, resolvingAgainstBaseURL: false)?.query,
              query.isEmpty == false,
              var components: URLComponents = URLComponents(url: siteURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.path = "/rss"
        components.query = query
        components.fragment = nil
        return components.url
    }

    private func appendCandidate(_ url: URL, to candidates: inout [URL]) {
        guard self.shouldKeepCandidate(url) else {
            return
        }

        let normalized: String = self.normalizedCandidateString(url)
        guard candidates.contains(where: { self.normalizedCandidateString($0) == normalized }) == false else {
            return
        }

        candidates.append(url)
    }

    private func shouldKeepCandidate(_ url: URL) -> Bool {
        guard let scheme: String = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else {
            return false
        }

        let lowercased: String = url.absoluteString.lowercased()
        return lowercased.contains("rss")
            || lowercased.contains("feed")
            || lowercased.contains("atom")
            || lowercased.hasSuffix(".xml")
    }

    private func shouldKeepHTMLCandidate(_ url: URL, selector: String, siteURL: URL) -> Bool {
        if selector.hasPrefix("link[rel") {
            return true
        }

        return url.host?.lowercased() == siteURL.host?.lowercased()
    }

    private func normalizedCandidateString(_ url: URL) -> String {
        var components: URLComponents? = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil

        if let path: String = components?.path,
           path.count > 1,
           path.hasSuffix("/") {
            components?.path = String(path.dropLast())
        }

        return components?.url?.absoluteString ?? url.absoluteString
    }

    private static func looksLikeFeedDocument(_ text: String) -> Bool {
        let prefix: String = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(8_192)
            .lowercased()

        guard prefix.isEmpty == false else {
            return false
        }

        if prefix.hasPrefix("<!doctype html")
            || prefix.hasPrefix("<html")
            || prefix.hasPrefix("{")
            || prefix.hasPrefix("[") {
            return false
        }

        let bodyStart: String = Self.xmlBodyStart(from: prefix)
        return bodyStart.hasPrefix("<rss")
            || bodyStart.hasPrefix("<feed")
            || bodyStart.hasPrefix("<rdf:rdf")
    }

    private static func textPreview(from data: Data) -> String {
        if let string: String = String(data: data.prefix(8_192), encoding: .utf8) {
            return string
        }

        return String(decoding: data.prefix(8_192), as: UTF8.self)
    }

    private static func xmlBodyStart(from text: String) -> String {
        var current: String = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if current.hasPrefix("<?xml"),
           let endIndex: String.Index = current.range(of: "?>")?.upperBound {
            current = String(current[endIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        while current.hasPrefix("<!--"),
              let endIndex: String.Index = current.range(of: "-->")?.upperBound {
            current = String(current[endIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if current.hasPrefix("<?xml-stylesheet"),
           let endIndex: String.Index = current.range(of: "?>")?.upperBound {
            current = String(current[endIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return current
    }

    private static func compactPreview(_ text: String) -> String {
        let collapsed: String = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let limit: Int = 120

        if collapsed.count <= limit {
            return collapsed
        }

        return String(collapsed.prefix(limit))
    }

    private static func nonFeedPreview(from text: String) -> String {
        let bodyStart: String = Self.xmlBodyStart(
            from: text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(8_192)
                .lowercased()
        )

        if bodyStart.hasPrefix("<!doctype html") || bodyStart.hasPrefix("<html") {
            return "html-document"
        }

        if bodyStart.hasPrefix("{") || bodyStart.hasPrefix("[") {
            return "json-document"
        }

        if let rootTag: String = Self.rootTagName(from: bodyStart) {
            return "root=<\(rootTag)>"
        }

        return Self.compactPreview(text)
    }

    private static func rootTagName(from text: String) -> String? {
        guard text.hasPrefix("<") else {
            return nil
        }

        guard text.hasPrefix("<!") == false,
              text.hasPrefix("<?") == false else {
            return nil
        }

        let disallowedCharacters: CharacterSet = CharacterSet(charactersIn: " \n\r\t>/")
        let startIndex: String.Index = text.index(after: text.startIndex)
        guard let endIndex: String.Index = text[startIndex...].firstIndex(where: { character in
            return String(character).rangeOfCharacter(from: disallowedCharacters) != nil
        }) else {
            return nil
        }

        let tagName: String = String(text[startIndex..<endIndex])
        return tagName.isEmpty ? nil : tagName
    }

    private func logAccepted(_ url: URL, title: String, count: Int) {
        #if DEBUG
        print(
            "[BrowseCraftRSSDiscovery] accept feed=\(url.absoluteString) " +
            "title=\(title) items=\(count)"
        )
        #endif
    }

    private func logRejected(_ url: URL, reason: String) {
        #if DEBUG
        print("[BrowseCraftRSSDiscovery] reject feed=\(url.absoluteString) reason=\(reason)")
        #endif
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed: String = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
