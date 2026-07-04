import BrowseCraftCore
import Foundation
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

    @Test func debugSessionMapsToSourceDebugSnapshot() {
        let issue = RuleDebugIssue(
            id: "issue-1",
            severity: .warning,
            category: .fieldMissing,
            stage: .list,
            ruleID: "discover",
            field: .cover,
            message: "Cover is missing."
        )
        let session = RuleDebugSession(
            id: "debug-1",
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            completedAt: Date(timeIntervalSince1970: 1_800_000_002),
            input: RuleDebugInput(
                sourceID: "source",
                sourceName: "Example",
                stage: .list,
                pageID: "home",
                tabID: "latest",
                ruleID: "discover",
                keyword: nil,
                page: 1,
                url: "https://example.com/list",
                context: nil
            ),
            requestLogs: [
                RuleDebugRequestLog(
                    id: "request-1",
                    stage: .list,
                    url: "https://example.com/list",
                    method: "GET",
                    requestSummary: RuleDebugRequestSummary(
                        needsWebView: false,
                        autoScroll: false,
                        scope: "page",
                        mergePolicy: "override",
                        cookiePolicy: "read",
                        charset: "utf8",
                        headerCount: 2,
                        hasBody: false
                    ),
                    startedAt: Date(timeIntervalSince1970: 1_800_000_000),
                    completedAt: Date(timeIntervalSince1970: 1_800_000_001),
                    responseSummary: RuleDebugResponseSummary(
                        statusCode: 200,
                        contentLength: 512,
                        finalURL: "https://example.com/list"
                    ),
                    errorMessage: nil
                )
            ],
            extractionLogs: [
                RuleDebugExtractionLog(
                    id: "extract-1",
                    stage: .list,
                    ruleID: "discover",
                    selector: "a.item",
                    field: .item,
                    candidateCount: 4,
                    outputCount: 3,
                    samples: ["One", "Two"],
                    message: "Selected list item candidates."
                )
            ],
            previewItems: [
                RuleDebugPreviewItem(
                    id: "preview-1",
                    title: "One",
                    detailURL: "https://example.com/comics/1",
                    chapterURL: nil,
                    coverURL: "https://example.com/cover.jpg",
                    imageURL: nil,
                    latestText: "第01话",
                    sourceIndex: 0,
                    issues: [issue]
                )
            ],
            pagination: nil,
            candidateReport: nil,
            issues: [issue]
        )

        let snapshot = session.sourceDebugSnapshot

        #expect(snapshot.id == "debug-1")
        #expect(snapshot.status == .succeeded)
        #expect(snapshot.input.operation == .list)
        #expect(snapshot.input.pageID == "home")
        #expect(snapshot.requestLogs.first?.requestSummary.headerCount == 2)
        #expect(snapshot.requestLogs.first?.responseSummary?.statusCode == 200)
        #expect(snapshot.extractionLogs.first?.field == .item)
        #expect(snapshot.previewItems.first?.issues.first?.category == .fieldMissing)
        #expect(snapshot.issues.first?.severity == .warning)
    }
}
