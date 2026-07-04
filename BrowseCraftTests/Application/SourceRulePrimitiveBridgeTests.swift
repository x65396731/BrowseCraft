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

    @Test func candidateReportMapsToSourceRuleCandidateReport() {
        let warning = RuleCandidateWarning(
            id: "warning-1",
            severity: .warning,
            category: .tooFewMatches,
            message: "Only one next-page candidate matched."
        )
        let candidate = RuleCandidate(
            id: "candidate-1",
            field: .nextPage,
            stage: .list,
            selector: "a.next",
            selectorKind: .css,
            function: .url,
            param: "href",
            score: RuleCandidateScore(
                value: 2,
                confidence: .high,
                reasons: ["rel=next"]
            ),
            evidence: RuleCandidateEvidence(
                candidateCount: 3,
                matchedCount: 1,
                sampleValues: ["/list?page=2"],
                sampleAttributes: ["rel": ["next"]],
                ancestorHints: ["nav.pagination"]
            ),
            warnings: [warning],
            source: .paginationLink
        )
        let report = RuleCandidateReport(
            id: "report-1",
            sourceID: "source",
            sourceName: "Example",
            stage: .list,
            pageID: "home",
            ruleID: "discover",
            url: "https://example.com/list",
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            candidates: [candidate],
            summary: RuleCandidateSummary(
                candidateCount: 1,
                highConfidenceCount: 1,
                warningCount: 1,
                coveredFields: [.nextPage]
            )
        )

        let sourceReport = report.sourceRuleCandidateReport

        #expect(sourceReport.id == "report-1")
        #expect(sourceReport.operation == .list)
        #expect(sourceReport.candidates.first?.field == .nextPage)
        #expect(sourceReport.candidates.first?.selectorKind == .css)
        #expect(sourceReport.candidates.first?.function == .url)
        #expect(sourceReport.candidates.first?.score.value == 1)
        #expect(sourceReport.candidates.first?.warnings.first?.category == .tooFewMatches)
        #expect(sourceReport.candidates.first?.source == .paginationLink)
        #expect(sourceReport.summary.coveredFields == [.nextPage])
    }

    @Test func siteRuleMapsToBrowseCraftRuleSchemaThroughJSONShape() throws {
        let json = """
        {
          "version": 2,
          "name": "Example",
          "baseUrl": "https://example.com",
          "site": {
            "name": "Example",
            "domain": "example.com",
            "baseURL": "https://example.com",
            "displayMode": "grid"
          },
          "pages": [
            {
              "id": "home",
              "title": "Home",
              "type": "home",
              "ruleRefs": { "list": "discover" }
            },
            {
              "id": "reader",
              "title": "Reader",
              "type": "reader",
              "ruleRefs": { "gallery": "reader" }
            }
          ],
          "ruleSets": {
            "listRules": [
              {
                "id": "discover",
                "url": "https://example.com/list/{page}",
                "item": ".card",
                "title": ".title",
                "link": ".title@href",
                "type": "comic",
                "fields": {
                  "title": { "selector": ".title", "function": "text" },
                  "detailURL": { "selector": ".title", "function": "url", "param": "href" }
                }
              }
            ],
            "galleryRules": [
              {
                "id": "reader",
                "imageItem": "img.page",
                "imageUrl": "this@src",
                "image": { "selector": "img.page", "function": "url", "param": "src" }
              }
            ]
          },
          "list": {
            "url": "https://example.com/list/{page}",
            "item": ".card",
            "title": ".title",
            "link": ".title@href",
            "type": "comic"
          }
        }
        """
        let data = try #require(json.data(using: .utf8))
        let rule = try JSONDecoder().decode(SiteRule.self, from: data)
        let schema = try rule.browseCraftRuleSchema()

        #expect(schema.name == "Example")
        #expect(schema.pages?.first?.isListEntryPage == true)
        #expect(schema.pages?.last?.isGalleryEntryPage == true)
        #expect(schema.ruleSets?.listRule(id: "discover")?.fields?.title.function == .text)
        #expect(schema.ruleSets?.galleryRule(id: "reader")?.image?.function == .url)
        #expect(schema.ruleSets?.listRule(id: " ") == nil)
    }
}
