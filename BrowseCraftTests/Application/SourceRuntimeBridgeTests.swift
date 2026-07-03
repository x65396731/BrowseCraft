import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft

// 中文注释：P3-4 App/Core bridge 合同测试，防止 Core runtime 字段扩展后 App 侧桥接静默丢字段。
struct SourceRuntimeBridgeTests {
    @Test func sourceDefinitionBridgeMapsOwnershipRuleMetadataAndBaseURLFallback() throws {
        let bridge: SourceDefinitionBridge = SourceDefinitionBridge()
        let builtInSource: Source = try Self.source(id: "built-in.example")
        let userSource: Source = try Self.source(id: "user.example")
        var invalidBaseURLSource: Source = userSource
        invalidBaseURLSource.baseURL = "   "

        let builtInDefinition: SourceDefinition = bridge.definition(from: builtInSource)
        let userDefinition: SourceDefinition = bridge.definition(from: userSource)
        let fallbackDefinition: SourceDefinition = bridge.definition(from: invalidBaseURLSource)

        #expect(builtInDefinition.id == "built-in.example")
        #expect(builtInDefinition.kind == .rule)
        #expect(builtInDefinition.name == "Complete V2 Site")
        #expect(builtInDefinition.baseURL.absoluteString == "https://example.test")
        #expect(builtInDefinition.version == 2)
        #expect(builtInDefinition.ownership == .builtIn)
        #expect(builtInDefinition.rule?.ruleID == "built-in.example")
        #expect(builtInDefinition.rule?.schemaVersion == 2)
        #expect(builtInDefinition.rule?.isEditable == false)
        #expect(builtInDefinition.rss == nil)
        #expect(builtInDefinition.plugin == nil)

        #expect(userDefinition.ownership == .user)
        #expect(userDefinition.rule?.isEditable == true)
        #expect(fallbackDefinition.baseURL.absoluteString == "about:blank")
    }

    @Test func inputBridgeKeepsListSearchContextAndRequestOverride() throws {
        let bridge: SourceRuntimeInputBridge = SourceRuntimeInputBridge()
        let source: Source = try Self.source(id: "user.example")
        let listContext = ListContext(
            pageId: "home",
            tabId: "discover",
            sectionId: "main-grid",
            listRuleId: "home-list",
            sectionRole: .main
        )
        let overrideURL: URL = try #require(URL(string: "https://example.test/list?page=2"))

        let listInput: SourceListInput = bridge.listInput(
            source: source,
            page: 2,
            listContext: listContext,
            urlOverride: overrideURL,
            headers: ["User-Agent": "BrowseCraft"],
            debugMode: true
        )
        let searchInput: SourceSearchInput = bridge.searchInput(
            source: source,
            keyword: "one piece",
            page: 3,
            listContext: listContext,
            ruleID: "search",
            urlOverride: overrideURL,
            headers: ["Accept-Language": "zh-Hans"],
            debugMode: false
        )

        #expect(listInput.page == 2)
        #expect(listInput.urlOverride == overrideURL)
        #expect(listInput.context.sourceID == "user.example")
        #expect(listInput.context.operation == .list)
        #expect(listInput.context.pageID == "home")
        #expect(listInput.context.tabID == "discover")
        #expect(listInput.context.sectionID == "main-grid")
        #expect(listInput.context.sectionRole == "main")
        #expect(listInput.context.ruleID == "home-list")
        #expect(listInput.context.requestOverride?.url == overrideURL)
        #expect(listInput.context.requestOverride?.headers["User-Agent"] == "BrowseCraft")
        #expect(listInput.context.debugMode)

        #expect(searchInput.keyword == "one piece")
        #expect(searchInput.page == 3)
        #expect(searchInput.urlOverride == overrideURL)
        #expect(searchInput.context.operation == .search)
        #expect(searchInput.context.ruleID == "search")
        #expect(searchInput.context.requestOverride?.headers["Accept-Language"] == "zh-Hans")
        #expect(searchInput.context.debugMode == false)
    }

    @Test func inputBridgeKeepsDetailReaderOperationAndRejectsBlankURLs() throws {
        let bridge: SourceRuntimeInputBridge = SourceRuntimeInputBridge()
        let source: Source = try Self.source(id: "user.example")
        let listContext = ListContext(
            pageId: "home",
            tabId: "latest",
            sectionId: "main-grid",
            listRuleId: "latest-list",
            sectionRole: .category
        )

        let detailInput: SourceDetailInput = try #require(
            bridge.detailInput(
                source: source,
                detailURLString: "  https://example.test/comics/1  ",
                listContext: listContext,
                ruleID: "detail",
                debugMode: true
            )
        )
        let readerInput: SourceReaderInput = try #require(
            bridge.readerInput(
                source: source,
                chapterURLString: "https://example.test/chapters/1",
                listContext: listContext,
                ruleID: "reader-gallery",
                debugMode: false
            )
        )

        #expect(detailInput.detailURL.absoluteString == "https://example.test/comics/1")
        #expect(detailInput.context.operation == .detail)
        #expect(detailInput.context.ruleID == "detail")
        #expect(detailInput.context.sectionRole == "category")
        #expect(detailInput.context.debugMode)
        #expect(bridge.detailInput(source: source, detailURLString: "   ", listContext: nil, ruleID: nil) == nil)

        #expect(readerInput.chapterURL.absoluteString == "https://example.test/chapters/1")
        #expect(readerInput.context.operation == .reader)
        #expect(readerInput.context.ruleID == "reader-gallery")
        #expect(readerInput.context.debugMode == false)
        #expect(bridge.readerInput(source: source, chapterURLString: "\n", listContext: nil, ruleID: nil) == nil)
    }

    @Test func outputBridgeMapsItemsChaptersReaderAndPassesDiagnosticsThrough() throws {
        let bridge: SourceRuntimeOutputBridge = SourceRuntimeOutputBridge()
        let diagnostics: SourceRuntimeDiagnostics = SourceRuntimeDiagnostics.partial(
            requestLogs: [
                SourceRequestLog(
                    url: try #require(URL(string: "https://example.test/list")),
                    method: "GET",
                    headerCount: 1,
                    contentLength: 128
                )
            ],
            extractionLogs: [
                SourceExtractionLog(
                    field: "item",
                    selector: ".card",
                    candidateCount: 2,
                    outputCount: 1
                )
            ],
            issues: [
                SourceRuntimeIssue(
                    id: "runtime.partial",
                    severity: .warning,
                    message: "One item was skipped."
                )
            ],
            candidateSummary: SourceCandidateSummary(
                field: "item",
                totalCandidates: 2,
                acceptedCandidates: 1,
                warningCount: 1,
                topSamples: ["Title"]
            )
        )
        let pagination: SourcePagination = try #require(
            SourcePagination.next(
                nextPageURLString: "https://example.test/list?page=2",
                nextPage: 2
            )
        )
        let item = ContentItem(
            id: "item-1",
            sourceId: "user.example",
            title: "Title",
            detailURL: "https://example.test/comics/1",
            coverURL: "   ",
            type: .comic,
            latestText: "第01话"
        )
        let listOutput: SourceListOutput = bridge.listOutput(
            items: [item],
            pagination: pagination,
            diagnostics: diagnostics
        )
        let detailOutput: SourceDetailOutput = bridge.detailOutput(
            chapters: [
                ChapterLink(title: "第01话", url: "https://example.test/chapters/1"),
                ChapterLink(title: "invalid", url: "   ")
            ],
            diagnostics: diagnostics
        )
        let readerOutput: SourceReaderOutput = bridge.readerOutput(
            chapter: ReaderChapter(
                sourceId: "user.example",
                comicTitle: "Comic",
                chapterTitle: "第01话",
                chapterURL: "https://example.test/chapters/1",
                catalogURL: nil,
                previousChapterURL: nil,
                nextChapterURL: nil,
                pageImageURLs: [
                    "https://example.test/images/1.jpg",
                    "   ",
                    "https://example.test/images/2.jpg"
                ]
            ),
            diagnostics: diagnostics
        )

        #expect(listOutput.items.count == 1)
        #expect(listOutput.items[0].id == "item-1")
        #expect(listOutput.items[0].title == "Title")
        #expect(listOutput.items[0].detailURL?.absoluteString == "https://example.test/comics/1")
        #expect(listOutput.items[0].coverURL == nil)
        #expect(listOutput.items[0].latestText == "第01话")
        #expect(listOutput.pagination == pagination)
        #expect(listOutput.diagnostics == diagnostics)

        #expect(detailOutput.chapters.count == 1)
        #expect(detailOutput.chapters[0].id == "https://example.test/chapters/1")
        #expect(detailOutput.chapters[0].title == "第01话")
        #expect(detailOutput.chapters[0].url.absoluteString == "https://example.test/chapters/1")
        #expect(detailOutput.diagnostics == diagnostics)

        #expect(readerOutput.chapter.title == "第01话")
        #expect(readerOutput.chapter.imageURLs.map(\.absoluteString) == [
            "https://example.test/images/1.jpg",
            "https://example.test/images/2.jpg"
        ])
        #expect(readerOutput.diagnostics == diagnostics)
    }

    private static func source(id: String) throws -> Source {
        let rule: SiteRule = try JSONDecoder().decode(
            SiteRule.self,
            from: Data(RuleJSONFixtures.completeV2SiteRule.utf8)
        )
        let now: Date = Date(timeIntervalSince1970: 1_000)

        return Source(
            id: id,
            name: rule.name,
            baseURL: rule.baseUrl,
            type: .html,
            rule: rule,
            enabled: true,
            createdAt: now,
            updatedAt: now
        )
    }
}
