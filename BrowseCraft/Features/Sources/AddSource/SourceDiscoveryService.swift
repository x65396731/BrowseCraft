import BrowseCraftDomain
import Foundation

struct SourceDiscoveryService: Sendable {
    private let assessVideoGenerationInputUseCase: AssessVideoGenerationInputUseCase

    init(
        assessVideoGenerationInputUseCase: AssessVideoGenerationInputUseCase
    ) {
        self.assessVideoGenerationInputUseCase = assessVideoGenerationInputUseCase
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
