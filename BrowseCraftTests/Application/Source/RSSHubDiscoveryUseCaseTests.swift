import Foundation
import Testing
@testable import BrowseCraft

struct RSSHubDiscoveryUseCaseTests {
    @Test func directXMLFeedURLBypassesRSSHubDiscovery() async throws {
        let radarLoader: RSSHubDiscoveryRecordingPageDataLoader = RSSHubDiscoveryRecordingPageDataLoader(
            responsesByURL: [:]
        )
        let feedURL: URL = try #require(URL(string: "https://www.bmpi.dev/index.xml"))
        let feedLoader: RSSHubDiscoveryRecordingFeedLoader = RSSHubDiscoveryRecordingFeedLoader(
            feedsByURL: [
                feedURL.absoluteString: RSSFeed(
                    title: "BMPI",
                    items: [
                        RSSFeedItem(
                            title: "Latest post",
                            link: URL(string: "https://www.bmpi.dev/post/latest"),
                            summary: nil,
                            coverURL: nil,
                            publishedAt: nil,
                            guid: nil
                        )
                    ]
                )
            ]
        )
        let useCase: DiscoverRSSFeedsUseCase = DiscoverRSSFeedsUseCase(
            rssFeedLoader: feedLoader,
            loadRSSHubDiscoveryCandidatesUseCase: LoadRSSHubDiscoveryCandidatesUseCase(
                pageDataLoader: radarLoader
            )
        )

        let results: [DiscoveredRSSFeedItem] = try await useCase.execute(
            DiscoverRSSFeedsInput(siteURLString: "https://www.bmpi.dev/index.xml")
        )

        let result: DiscoveredRSSFeedItem = try #require(results.first)
        #expect(results.count == 1)
        #expect(result.feedURL == feedURL)
        #expect(result.title == "BMPI")
        #expect(feedLoader.requestedURLs == [feedURL])
        #expect(radarLoader.requestedURLs.isEmpty)
    }

    @Test func directAnyFeederPlinkURLBypassesRSSHubDiscovery() async throws {
        let radarLoader: RSSHubDiscoveryRecordingPageDataLoader = RSSHubDiscoveryRecordingPageDataLoader(
            responsesByURL: [:]
        )
        let feedURL: URL = try #require(URL(string: "https://plink.anyfeeder.com/zaobao/realtime/world"))
        let feedLoader: RSSHubDiscoveryRecordingFeedLoader = RSSHubDiscoveryRecordingFeedLoader(
            feedsByURL: [
                feedURL.absoluteString: RSSFeed(
                    title: "Zaobao World",
                    items: [
                        RSSFeedItem(
                            title: "First item",
                            link: URL(string: "https://www.zaobao.com.sg/realtime/world/story-1"),
                            summary: nil,
                            coverURL: nil,
                            publishedAt: nil,
                            guid: nil
                        )
                    ]
                )
            ]
        )
        let useCase: DiscoverRSSFeedsUseCase = DiscoverRSSFeedsUseCase(
            rssFeedLoader: feedLoader,
            loadRSSHubDiscoveryCandidatesUseCase: LoadRSSHubDiscoveryCandidatesUseCase(
                pageDataLoader: radarLoader
            )
        )

        let results: [DiscoveredRSSFeedItem] = try await useCase.execute(
            DiscoverRSSFeedsInput(
                siteURLString: "https://plink.anyfeeder.com/zaobao/realtime/world"
            )
        )

        let result: DiscoveredRSSFeedItem = try #require(results.first)
        #expect(results.count == 1)
        #expect(result.feedURL == feedURL)
        #expect(result.siteURL.absoluteString == "https://plink.anyfeeder.com/zaobao/realtime/world")
        #expect(result.title == "Zaobao World")
        #expect(result.itemCount == 1)
        #expect(result.firstItemTitle == "First item")
        #expect(feedLoader.requestedURLs == [feedURL])
        #expect(radarLoader.requestedURLs.isEmpty)
    }

    @Test func ignoresRSSHubRuleWhenInputURLCannotFillTargetParameters() async throws {
        let radarLoader: RSSHubDiscoveryRecordingPageDataLoader = RSSHubDiscoveryRecordingPageDataLoader(
            responsesByURL: [
                "https://rsshub.app/api/radar/rules/anyfeeder.com": Data(Self.missingParameterRadarRules.utf8)
            ]
        )
        let feedLoader: RSSHubDiscoveryRecordingFeedLoader = RSSHubDiscoveryRecordingFeedLoader(
            feedsByURL: [:]
        )
        let useCase: DiscoverRSSFeedsUseCase = DiscoverRSSFeedsUseCase(
            rssFeedLoader: feedLoader,
            loadRSSHubDiscoveryCandidatesUseCase: LoadRSSHubDiscoveryCandidatesUseCase(
                pageDataLoader: radarLoader
            )
        )

        let results: [DiscoveredRSSFeedItem] = try await useCase.execute(
            DiscoverRSSFeedsInput(
                siteURLString: "https://plink.anyfeeder.com/zaobao/realtime"
            )
        )

        #expect(results.isEmpty)
        #expect(feedLoader.requestedURLs.isEmpty)
    }

    private static let anyFeederRadarRules: String = """
    {
      "_name": "AnyFeeder",
      "plink": [
        {
          "title": "Zaobao Realtime",
          "source": ["/zaobao/realtime/:section"],
          "target": "/zaobao/realtime/:section"
        }
      ]
    }
    """

    private static let missingParameterRadarRules: String = """
    {
      "_name": "AnyFeeder",
      "plink": [
        {
          "title": "Zaobao Realtime",
          "source": ["/zaobao/realtime"],
          "target": "/zaobao/realtime/:section"
        }
      ]
    }
    """
}

private final class RSSHubDiscoveryRecordingPageDataLoader: PageDataLoader {
    private let responsesByURL: [String: Data]
    private(set) var requestedURLs: [URL] = []

    init(responsesByURL: [String: Data]) {
        self.responsesByURL = responsesByURL
    }

    func getData(from url: URL, request: RequestConfig?) async throws -> Data {
        self.requestedURLs.append(url)

        if let response: Data = self.responsesByURL[url.absoluteString] {
            return response
        }

        throw RSSHubDiscoveryTestError.missingMockResponse(url.absoluteString)
    }
}

private final class RSSHubDiscoveryRecordingFeedLoader: RSSFeedLoading {
    private let feedsByURL: [String: RSSFeed]
    private(set) var requestedURLs: [URL] = []

    init(feedsByURL: [String: RSSFeed]) {
        self.feedsByURL = feedsByURL
    }

    func load(feedURL: URL) async throws -> RSSFeed {
        self.requestedURLs.append(feedURL)

        if let feed: RSSFeed = self.feedsByURL[feedURL.absoluteString] {
            return feed
        }

        throw RSSHubDiscoveryTestError.missingMockResponse(feedURL.absoluteString)
    }
}

private enum RSSHubDiscoveryTestError: Error {
    case missingMockResponse(String)
}
