import BrowseCraftDomain
import Foundation

struct SourceDiscoveryService: Sendable {
    private let assessVideoGenerationInputUseCase: AssessVideoGenerationInputUseCase
    /// 中文注释：只有 DEBUG 演示模式（拍商城截图）传入，替代真实的本机检查；正式装配为 nil。
    private let assessmentOverride: (@Sendable (String) async throws -> VideoGenerationInputPreflight)?

    init(
        assessVideoGenerationInputUseCase: AssessVideoGenerationInputUseCase,
        assessmentOverride: (@Sendable (String) async throws -> VideoGenerationInputPreflight)? = nil
    ) {
        self.assessVideoGenerationInputUseCase = assessVideoGenerationInputUseCase
        self.assessmentOverride = assessmentOverride
    }

    func assessVideoGenerationInput(
        siteURLString: String,
        progress: VideoGenerationInputProgressHandler? = nil
    ) async throws -> VideoGenerationInputPreflight {
        if let assessmentOverride: @Sendable (String) async throws -> VideoGenerationInputPreflight = self.assessmentOverride {
            return try await assessmentOverride(siteURLString)
        }
        return try await self.assessVideoGenerationInputUseCase.execute(
            siteURLString: siteURLString,
            progress: progress
        )
    }
}
