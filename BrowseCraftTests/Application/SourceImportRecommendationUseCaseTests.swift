import Foundation
import BrowseCraftCore
import Testing
@testable import BrowseCraft

// 中文注释：SourceImportRecommendationUseCaseTests 固定 P4.6 添加来源推荐启发式边界。
struct SourceImportRecommendationUseCaseTests {
    @Test func videoHTMLRecommendsVideoRuntimeWithoutRuleFallback() {
        let useCase: RecommendSourceImportOptionUseCase = RecommendSourceImportOptionUseCase()
        let draft: SourceImportDraft = SourceImportDraft(entryURL: "https://video.example.test")
        let html: String = "<html><body><video src=\"movie.mp4\"></video></body></html>"

        let recommendation: SourceImportRecommendation = useCase.execute(draft: draft, html: html)

        #expect(recommendation.optionKind == .videoSource)
        #expect(recommendation.sourceType == .html)
        #expect(recommendation.configurationKind == .video)
        #expect(recommendation.reasons == [.htmlContainsVideoElement])
        #expect(recommendation.warnings == ["Video sources are routed through the video runtime entry."])
    }

    @Test func knownRuleTemplateURLRecommendsComicRuntimeSource() {
        let useCase: RecommendSourceImportOptionUseCase = RecommendSourceImportOptionUseCase()
        let draft: SourceImportDraft = SourceImportDraft(entryURL: "https://mycomic.com/cn")

        let recommendation: SourceImportRecommendation = useCase.execute(draft: draft)

        #expect(recommendation.optionKind == .comicSource)
        #expect(recommendation.sourceType == .html)
        #expect(recommendation.configurationKind == .comic)
        #expect(recommendation.confidence == .high)
        #expect(recommendation.reasons == [.knownRuleTemplate])
    }

    @Test func unknownWebsiteFallsBackToLowConfidenceComicRecommendation() {
        let useCase: RecommendSourceImportOptionUseCase = RecommendSourceImportOptionUseCase()
        let draft: SourceImportDraft = SourceImportDraft(entryURL: "https://unknown.example.test")

        let recommendation: SourceImportRecommendation = useCase.execute(draft: draft)

        #expect(recommendation.optionKind == .comicSource)
        #expect(recommendation.sourceType == .html)
        #expect(recommendation.configurationKind == .comic)
        #expect(recommendation.confidence == .low)
        #expect(recommendation.reasons == [.userSelectedOption])
    }
}
