import Foundation
import BrowseCraftCore
import Testing
@testable import BrowseCraft

// 中文注释：SourceImportRecommendationTests 固定 P4 添加来源推荐模型的中性边界。
struct SourceImportRecommendationTests {
    @Test func defaultImportOptionsUseUserFacingKindsAndInternalConfigKinds() {
        let options: [SourceImportOption] = SourceImportOption.defaultOptions

        #expect(options.map(\.kind) == [
            .comicSource,
            .videoSource,
            .rssFeedURL
        ])

        #expect(options[0].defaultSourceType == .html)
        #expect(options[0].defaultConfigurationKind == .comic)
        #expect(options[1].defaultSourceType == .html)
        #expect(options[1].defaultConfigurationKind == .video)
        #expect(options[2].requiresURLInput == true)
        #expect(options[2].defaultSourceType == .rss)
        #expect(options[2].defaultConfigurationKind == .rss)
    }

    @Test func recommendationAppliesInternalAxesWithoutOverwritingDraftText() {
        let draft: SourceImportDraft = SourceImportDraft(
            name: " Example ",
            entryURL: " https://example.test ",
            sourceType: .html,
            configurationKind: nil,
            ruleJSON: "{ \"name\": \"Example\" }"
        )
        let recommendation: SourceImportRecommendation = SourceImportRecommendation(
            optionKind: .comicSource,
            sourceType: .html,
            configurationKind: .comic,
            confidence: .high,
            reasons: [.userSelectedOption]
        )

        let updatedDraft: SourceImportDraft = recommendation.applying(to: draft)

        #expect(updatedDraft.name == draft.name)
        #expect(updatedDraft.entryURL == draft.entryURL)
        #expect(updatedDraft.ruleJSON == draft.ruleJSON)
        #expect(updatedDraft.sourceType == .html)
        #expect(updatedDraft.configurationKind == .comic)
        #expect(recommendation.isStrongRecommendation == true)
    }

    @Test func weakRecommendationCanStillRepresentWarnings() throws {
        let recommendation: SourceImportRecommendation = SourceImportRecommendation(
            optionKind: .videoSource,
            sourceType: .html,
            configurationKind: .video,
            confidence: .medium,
            reasons: [.htmlContainsVideoElement],
            warnings: ["Video sources are routed through the video runtime entry."]
        )

        let data: Data = try JSONEncoder().encode(recommendation)
        let decoded: SourceImportRecommendation = try JSONDecoder().decode(
            SourceImportRecommendation.self,
            from: data
        )

        #expect(decoded == recommendation)
        #expect(decoded.isStrongRecommendation == false)
        #expect(decoded.warnings == ["Video sources are routed through the video runtime entry."])
    }
}
