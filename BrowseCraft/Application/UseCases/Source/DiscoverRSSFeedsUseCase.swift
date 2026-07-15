import Foundation

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
    private let rssFeedLoader: any RSSFeedLoading
    private let loadRSSHubDiscoveryCandidatesUseCase: LoadRSSHubDiscoveryCandidatesUseCase
    private let maxCandidates: Int

    init(
        rssFeedLoader: any RSSFeedLoading,
        loadRSSHubDiscoveryCandidatesUseCase: LoadRSSHubDiscoveryCandidatesUseCase,
        maxCandidates: Int = 24
    ) {
        self.rssFeedLoader = rssFeedLoader
        self.loadRSSHubDiscoveryCandidatesUseCase = loadRSSHubDiscoveryCandidatesUseCase
        self.maxCandidates = maxCandidates
    }

    func execute(_ input: DiscoverRSSFeedsInput) async throws -> [DiscoveredRSSFeedItem] {
        let siteURL: URL = try self.siteURL(from: input.siteURLString)
        var candidates: [URL] = []
        var candidateTitlesByURL: [String: String] = [:]

        let hasDirectFeedCandidate: Bool = self.appendCandidate(
            siteURL,
            to: &candidates,
            requiresFeedLikeURL: self.isRSSHubURL(siteURL) == false
        )

        if hasDirectFeedCandidate {
            self.logDirectFeedCandidate(siteURL)
        } else if self.isRSSHubURL(siteURL) == false {
            do {
                let rssHubCandidates: [RSSHubDiscoveryCandidate] =
                    try await self.loadRSSHubDiscoveryCandidatesUseCase.execute(siteURL: siteURL)
                for rssHubCandidate in rssHubCandidates {
                    self.appendCandidate(
                        rssHubCandidate.feedURL,
                        to: &candidates,
                        requiresFeedLikeURL: false
                    )
                    candidateTitlesByURL[self.normalizedCandidateString(rssHubCandidate.feedURL)] = rssHubCandidate.title
                }
            } catch {
                self.logRSSHubDiscoveryFailed(siteURL, error: error)
            }
        }

        #if DEBUG
        print(
            "[BrowseCraftRSSDiscovery] start site=\(siteURL.absoluteString) " +
            "candidateCount=\(candidates.count)"
        )
        #endif

        var results: [DiscoveredRSSFeedItem] = []
        var blockingError: Error?
        for candidate in candidates.prefix(self.maxCandidates) {
            do {
                let feed: RSSFeed = try await self.rssFeedLoader.load(feedURL: candidate)
                guard feed.items.isEmpty == false else {
                    self.logRejected(candidate, reason: "empty-feed")
                    continue
                }

                let title: String = feed.title?.trimmedNonEmpty
                    ?? candidateTitlesByURL[self.normalizedCandidateString(candidate)]
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
                if self.isBlockingCandidateError(error) {
                    blockingError = blockingError ?? error
                }
                self.logRejected(candidate, reason: error.localizedDescription)
            }
        }

        if results.isEmpty,
           let blockingError: Error {
            throw blockingError
        }

        return results
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

    @discardableResult
    private func appendCandidate(
        _ url: URL,
        to candidates: inout [URL],
        requiresFeedLikeURL: Bool = true
    ) -> Bool {
        let candidateURL: URL = self.secureRSSCandidateURLIfNeeded(url)
        guard self.isHTTPURL(candidateURL),
              requiresFeedLikeURL == false || self.shouldKeepCandidate(candidateURL) else {
            return false
        }

        let normalized: String = self.normalizedCandidateString(candidateURL)
        guard candidates.contains(where: { self.normalizedCandidateString($0) == normalized }) == false else {
            return false
        }

        candidates.append(candidateURL)
        return true
    }

    private func secureRSSCandidateURLIfNeeded(_ url: URL) -> URL {
        guard url.scheme?.lowercased() == "http",
              var components: URLComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        components.scheme = "https"
        return components.url ?? url
    }

    private func shouldKeepCandidate(_ url: URL) -> Bool {
        let lowercasedHost: String = url.host?.lowercased() ?? ""
        let lowercasedPath: String = url.path.lowercased()
        let lowercasedQuery: String = url.query?.lowercased() ?? ""

        return self.isKnownDirectFeedURL(host: lowercasedHost, path: lowercasedPath)
            || self.isFeedSubdomain(lowercasedHost)
            || lowercasedPath.contains("rss")
            || lowercasedPath.contains("feed")
            || lowercasedPath.contains("atom")
            || lowercasedPath.hasSuffix(".xml")
            || lowercasedQuery.contains("rss")
            || lowercasedQuery.contains("feed")
            || lowercasedQuery.contains("atom")
    }

    private func isKnownDirectFeedURL(host: String, path: String) -> Bool {
        if host == "plink.anyfeeder.com" {
            let pathComponents: [Substring] = path.split(separator: "/")
            return pathComponents.count >= 2
        }

        return false
    }

    private func isFeedSubdomain(_ host: String) -> Bool {
        guard let subdomain: String = host.split(separator: ".").first.map(String.init) else {
            return false
        }

        return subdomain == "feed"
            || subdomain == "feeds"
            || subdomain == "rss"
            || subdomain == "atom"
            || subdomain.hasPrefix("feed-")
            || subdomain.hasPrefix("feeds-")
            || subdomain.hasPrefix("rss-")
            || subdomain.hasPrefix("atom-")
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

    private func isHTTPURL(_ url: URL) -> Bool {
        guard let scheme: String = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else {
            return false
        }

        return true
    }

    private func isRSSHubURL(_ url: URL) -> Bool {
        return url.host?.lowercased().contains("rsshub") == true
    }

    private func isBlockingCandidateError(_ error: Error) -> Bool {
        guard let ruleExecutionError: RuleExecutionError = error as? RuleExecutionError else {
            return false
        }

        switch ruleExecutionError {
        case .antiBot, .network:
            return true
        case .selectorEmpty, .ruleConfiguration, .parserDiagnostics, .unknown:
            return false
        }
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

    private func logDirectFeedCandidate(_ url: URL) {
        #if DEBUG
        print(
            "[BrowseCraftRSSDiscovery] direct feed candidate " +
            "site=\(url.absoluteString) skipRSSHub=true"
        )
        #endif
    }

    private func logRSSHubDiscoveryFailed(_ siteURL: URL, error: Error) {
        #if DEBUG
        print(
            "[BrowseCraftRSSHub] discovery failed " +
            "site=\(siteURL.absoluteString) error=\(error)"
        )
        #endif
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed: String = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
