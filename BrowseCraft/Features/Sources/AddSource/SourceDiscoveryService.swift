import Foundation

struct SourceDiscoveryService: Sendable {
    private let discoverComicResourcesUseCase: DiscoverComicResourcesUseCase
    private let discoverVideoResourcesUseCase: DiscoverVideoResourcesUseCase
    private let discoverRSSFeedsUseCase: DiscoverRSSFeedsUseCase
    private let assessVideoGenerationInputUseCase: AssessVideoGenerationInputUseCase

    init(
        discoverComicResourcesUseCase: DiscoverComicResourcesUseCase,
        discoverVideoResourcesUseCase: DiscoverVideoResourcesUseCase,
        discoverRSSFeedsUseCase: DiscoverRSSFeedsUseCase,
        assessVideoGenerationInputUseCase: AssessVideoGenerationInputUseCase
    ) {
        self.discoverComicResourcesUseCase = discoverComicResourcesUseCase
        self.discoverVideoResourcesUseCase = discoverVideoResourcesUseCase
        self.discoverRSSFeedsUseCase = discoverRSSFeedsUseCase
        self.assessVideoGenerationInputUseCase = assessVideoGenerationInputUseCase
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

    func assessVideoGenerationInput(
        siteURLString: String,
        progress: VideoGenerationInputProgressHandler? = nil
    ) async throws -> VideoGenerationInputPreflight {
        return try await self.assessVideoGenerationInputUseCase.execute(
            siteURLString: siteURLString,
            progress: progress
        )
    }
}
