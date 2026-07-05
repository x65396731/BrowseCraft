import Foundation
import BrowseCraftCore
import Testing
@testable import BrowseCraft

// 中文注释：SourceImportDraftTests 固定 P4 添加来源草稿的中性边界。
struct SourceImportDraftTests {
    @Test func emptyDraftKeepsSourceImportNeutral() {
        let draft: SourceImportDraft = SourceImportDraft()

        #expect(draft.name == "")
        #expect(draft.entryURL == "")
        #expect(draft.contentType == nil)
        #expect(draft.sourceType == nil)
        #expect(draft.configurationKind == nil)
        #expect(draft.ruleJSON == nil)
        #expect(draft.hasMinimumEntryInput == false)
        #expect(draft.usesRuleConfiguration == false)
    }

    @Test func draftSeparatesContentTypeSourceTypeAndConfigurationKind() {
        let draft: SourceImportDraft = SourceImportDraft(
            name: " Video Source ",
            entryURL: " https://example.test/video ",
            contentType: .video,
            sourceType: .html,
            configurationKind: .rule
        )

        // 中文注释：用户理解的是内容形态；源站格式和内部 runtime config 是不同轴。
        #expect(draft.trimmedName == "Video Source")
        #expect(draft.trimmedEntryURL == "https://example.test/video")
        #expect(draft.contentType == .video)
        #expect(draft.sourceType == .html)
        #expect(draft.configurationKind == .rule)
        #expect(draft.hasMinimumEntryInput == true)
        #expect(draft.usesRuleConfiguration == true)
    }

    @Test func ruleJSONCanBeEntryInputWithoutForcingContentType() {
        let draft: SourceImportDraft = SourceImportDraft(
            ruleJSON: "  { \"name\": \"Example\" }  "
        )

        #expect(draft.trimmedRuleJSON == "{ \"name\": \"Example\" }")
        #expect(draft.contentType == nil)
        #expect(draft.sourceType == nil)
        #expect(draft.configurationKind == nil)
        #expect(draft.hasMinimumEntryInput == true)
        #expect(draft.usesRuleConfiguration == true)
    }

    @Test func draftCodableRoundTripPreservesNeutralAxes() throws {
        let draft: SourceImportDraft = SourceImportDraft(
            name: "Feed",
            entryURL: "https://example.test/rss.xml",
            contentType: .article,
            sourceType: .rss,
            configurationKind: .rss,
            ruleJSON: nil
        )

        let data: Data = try JSONEncoder().encode(draft)
        let decoded: SourceImportDraft = try JSONDecoder().decode(
            SourceImportDraft.self,
            from: data
        )

        #expect(decoded == draft)
        #expect(decoded.usesRuleConfiguration == false)
    }
}
