import BrowseCraftDomain
import Foundation

struct SourceDiscoveryService: Sendable {
    private let discoverComicResourcesUseCase: DiscoverComicResourcesUseCase
    private let discoverVideoResourcesUseCase: DiscoverVideoResourcesUseCase
    private let assessVideoGenerationInputUseCase: AssessVideoGenerationInputUseCase

    init(
        discoverComicResourcesUseCase: DiscoverComicResourcesUseCase,
        discoverVideoResourcesUseCase: DiscoverVideoResourcesUseCase,
        assessVideoGenerationInputUseCase: AssessVideoGenerationInputUseCase
    ) {
        self.discoverComicResourcesUseCase = discoverComicResourcesUseCase
        self.discoverVideoResourcesUseCase = discoverVideoResourcesUseCase
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
