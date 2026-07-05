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
            .websiteRuleJSON,
            .rulePackageJSON,
            .rssFeedURL,
            .scriptSource
        ])

        #expect(options[0].defaultContentType == .comic)
        #expect(options[0].defaultConfigurationKind == .rule)
        #expect(options[1].defaultContentType == .video)
        #expect(options[1].defaultConfigurationKind == .rule)
        #expect(options[2].acceptsRuleJSONInput == true)
        #expect(options[2].defaultConfigurationKind == .rule)
        #expect(options[4].requiresURLInput == true)
        #expect(options[4].defaultContentType == .article)
        #expect(options[4].defaultConfigurationKind == .rss)
        #expect(options[5].defaultConfigurationKind == .plugin)
    }

    @Test func recommendationAppliesInternalAxesWithoutOverwritingDraftText() {
        let draft: SourceImportDraft = SourceImportDraft(
            name: " Example ",
            entryURL: " https://example.test ",
            contentType: nil,
            sourceType: .html,
            configurationKind: nil,
            ruleJSON: "{ \"name\": \"Example\" }"
        )
        let recommendation: SourceImportRecommendation = SourceImportRecommendation(
            optionKind: .websiteRuleJSON,
            contentType: .comic,
            sourceType: .json,
            configurationKind: .rule,
            confidence: .high,
            reasons: [.ruleJSONDetected]
        )

        let updatedDraft: SourceImportDraft = recommendation.applying(to: draft)

        #expect(updatedDraft.name == draft.name)
        #expect(updatedDraft.entryURL == draft.entryURL)
        #expect(updatedDraft.ruleJSON == draft.ruleJSON)
        #expect(updatedDraft.contentType == .comic)
        #expect(updatedDraft.sourceType == .json)
        #expect(updatedDraft.configurationKind == .rule)
        #expect(recommendation.isStrongRecommendation == true)
    }

    @Test func weakRecommendationCanStillRepresentWarnings() throws {
        let recommendation: SourceImportRecommendation = SourceImportRecommendation(
            optionKind: .videoSource,
            contentType: .video,
            sourceType: .html,
            configurationKind: .rule,
            confidence: .medium,
            reasons: [.htmlContainsVideoElement],
            warnings: ["Video can still be parsed by a rule runtime."]
        )

        let data: Data = try JSONEncoder().encode(recommendation)
        let decoded: SourceImportRecommendation = try JSONDecoder().decode(
            SourceImportRecommendation.self,
            from: data
        )

        #expect(decoded == recommendation)
        #expect(decoded.isStrongRecommendation == false)
        #expect(decoded.warnings == ["Video can still be parsed by a rule runtime."])
    }
}
