import Foundation

struct SourceDiscoveryService: @unchecked Sendable {
    private let discoverComicResourcesUseCase: DiscoverComicResourcesUseCase
    private let discoverVideoResourcesUseCase: DiscoverVideoResourcesUseCase
    private let discoverRSSFeedsUseCase: DiscoverRSSFeedsUseCase

    init(
        discoverComicResourcesUseCase: DiscoverComicResourcesUseCase,
        discoverVideoResourcesUseCase: DiscoverVideoResourcesUseCase,
        discoverRSSFeedsUseCase: DiscoverRSSFeedsUseCase
    ) {
        self.discoverComicResourcesUseCase = discoverComicResourcesUseCase
        self.discoverVideoResourcesUseCase = discoverVideoResourcesUseCase
        self.discoverRSSFeedsUseCase = discoverRSSFeedsUseCase
    }

    func discoverComicResources(
        siteURLString: String,
        keyword: String
    ) async throws -> [TransientComicDiscoveryItem] {
        return try await self.discoverComicResourcesUseCase.execute(
            DiscoverComicResourcesInput(
                siteURLString: siteURLString,
                keyword: keyword
            )
        )
    }

    func discoverVideoResources(
        siteURLString: String,
        keyword: String
    ) async throws -> [TransientVideoDiscoveryItem] {
        return try await self.discoverVideoResourcesUseCase.execute(
            DiscoverVideoResourcesInput(
                siteURLString: siteURLString,
                keyword: keyword
            )
        )
    }

    func discoverRSSFeeds(siteURLString: String) async throws -> [DiscoveredRSSFeedItem] {
        return try await self.discoverRSSFeedsUseCase.execute(
            DiscoverRSSFeedsInput(siteURLString: siteURLString)
        )
    }
}
