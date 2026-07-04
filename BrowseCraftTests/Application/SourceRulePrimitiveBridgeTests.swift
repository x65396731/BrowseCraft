import BrowseCraftCore
import Testing
@testable import BrowseCraft

// 中文注释：P3-5.1 公共 primitive bridge 测试，锁定 App 现有枚举到 Core 枚举的映射。
struct SourceRulePrimitiveBridgeTests {
    @Test func debugStagesMapToRuntimeOperations() {
        #expect(RuleDebugStage.list.sourceRuntimeOperation == .list)
        #expect(RuleDebugStage.search.sourceRuntimeOperation == .search)
        #expect(RuleDebugStage.detail.sourceRuntimeOperation == .detail)
        #expect(RuleDebugStage.reader.sourceRuntimeOperation == .reader)

        #expect(SourceRuntimeOperation.list.ruleDebugStage == .list)
        #expect(SourceRuntimeOperation.search.ruleDebugStage == .search)
        #expect(SourceRuntimeOperation.detail.ruleDebugStage == .detail)
        #expect(SourceRuntimeOperation.reader.ruleDebugStage == .reader)
        #expect(SourceRuntimeOperation.debug.ruleDebugStage == nil)
    }

    @Test func debugAndCandidateFieldsMapToSourceRuleFields() {
        #expect(RuleDebugField.item.sourceRuleField == .item)
        #expect(RuleDebugField.title.sourceRuleField == .title)
        #expect(RuleDebugField.link.sourceRuleField == .link)
        #expect(RuleDebugField.cover.sourceRuleField == .cover)
        #expect(RuleDebugField.latestText.sourceRuleField == .latestText)
        #expect(RuleDebugField.chapter.sourceRuleField == .chapter)
        #expect(RuleDebugField.image.sourceRuleField == .image)
        #expect(RuleDebugField.unknown.sourceRuleField == .unknown)

        #expect(RuleCandidateField.section.sourceRuleField == .section)
        #expect(RuleCandidateField.item.sourceRuleField == .item)
        #expect(RuleCandidateField.title.sourceRuleField == .title)
        #expect(RuleCandidateField.link.sourceRuleField == .link)
        #expect(RuleCandidateField.cover.sourceRuleField == .cover)
        #expect(RuleCandidateField.latestText.sourceRuleField == .latestText)
        #expect(RuleCandidateField.chapterContainer.sourceRuleField == .chapterContainer)
        #expect(RuleCandidateField.chapterItem.sourceRuleField == .chapterItem)
        #expect(RuleCandidateField.chapterTitle.sourceRuleField == .chapterTitle)
        #expect(RuleCandidateField.chapterLink.sourceRuleField == .chapterLink)
        #expect(RuleCandidateField.image.sourceRuleField == .image)
        #expect(RuleCandidateField.nextPage.sourceRuleField == .nextPage)
        #expect(RuleCandidateField.unknown.sourceRuleField == .unknown)
    }

    @Test func selectorKindsAndExtractFunctionsRoundTripThroughCorePrimitives() {
        let selectorKinds: [SelectorKind] = [.css, .jsonPath, .xpath, .current]
        let functions: [ExtractFunction] = [
            .text,
            .html,
            .attr,
            .raw,
            .url,
            .decodeBase64,
            .removingPercentEncoding,
            .addingPercentEncoding,
            .replace,
            .decompressFromBase64,
            .reversed,
            .regexReplacement
        ]

        #expect(selectorKinds.map { kind in kind.sourceRuleSelectorKind.selectorKind } == selectorKinds)
        #expect(functions.map { function in function.sourceRuleExtractFunction.extractFunction } == functions)
    }
}
