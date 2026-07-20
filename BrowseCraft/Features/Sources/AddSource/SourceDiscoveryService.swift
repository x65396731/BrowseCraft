import Foundation

struct SourceDiscoveryService {
    private let discoverComicResourcesUseCase: DiscoverComicResourcesUseCase
    private let discoverVideoResourcesUseCase: DiscoverVideoResourcesUseCase
    private let discoverRSSFeedsUseCase: DiscoverRSSFeedsUseCase
    private let saveTemporaryResourceHistoryUseCase: SaveTemporaryResourceHistoryUseCase

    init(
        discoverComicResourcesUseCase: DiscoverComicResourcesUseCase,
        discoverVideoResourcesUseCase: DiscoverVideoResourcesUseCase,
        discoverRSSFeedsUseCase: DiscoverRSSFeedsUseCase,
        saveTemporaryResourceHistoryUseCase: SaveTemporaryResourceHistoryUseCase
    ) {
        self.discoverComicResourcesUseCase = discoverComicResourcesUseCase
        self.discoverVideoResourcesUseCase = discoverVideoResourcesUseCase
        self.discoverRSSFeedsUseCase = discoverRSSFeedsUseCase
        self.saveTemporaryResourceHistoryUseCase = saveTemporaryResourceHistoryUseCase
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

    func saveTemporaryHistory(_ history: TemporaryResourceHistory) throws {
        try self.saveTemporaryResourceHistoryUseCase.execute(history: history)
    }
}
