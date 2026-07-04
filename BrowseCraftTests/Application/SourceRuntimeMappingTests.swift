import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft

// 中文注释：P3 runtime 本地映射合同测试，防止 Core runtime 字段扩展后 App 侧映射静默丢字段。
struct SourceRuntimeMappingTests {
    @Test func sourceRuntimeResolverReturnsRuleRuntimeForRuleBackedSourceTypes() throws {
        let source: Source = try Self.source(id: "user.example")
        let resolver = SourceRuntimeResolver { source in
            return StubSourceRuntime(definition: SourceDefinitionMapper().definition(from: source))
        }

        let runtime: any SourceRuntime = try resolver.runtime(for: source)

        #expect(runtime.definition.id == "user.example")
        #expect(runtime.definition.kind == .rule)
        #expect(runtime.capabilities.supportsReader)
    }

    @Test func sourceRuntimeResolverRejectsRSSUntilRuntimeIsConnected() throws {
        var source: Source = try Self.source(id: "rss.example")
        source.type = .rss
        let resolver = SourceRuntimeResolver { source in
            return StubSourceRuntime(definition: SourceDefinitionMapper().definition(from: source))
        }

        do {
            _ = try resolver.runtime(for: source)
            Issue.record("Expected RSS runtime resolution to fail until P3-8.")
        } catch SourceRuntimeError.unsupported(.custom(let message)) {
            #expect(message.contains("P3-8"))
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }
    }

    @Test func refreshSourceRuntimeUseCaseBuildsListInputFromListContext() async throws {
        let source: Source = try Self.source(id: "user.example")
        let runtime = RecordingSourceRuntime(definition: SourceDefinitionMapper().definition(from: source))
        let useCase = RefreshSourceRuntimeUseCase(
            runtimeResolver: SourceRuntimeResolver { _ in
                return runtime
            }
        )
        let context = ListContext(
            pageId: "home",
            tabId: "latest",
            sectionId: "main-grid",
            listRuleId: "latest-list",
            sectionRole: .category
        )

        _ = try await useCase.execute(
            source: source,
            listContext: context,
            page: 3,
            debugMode: true
        )

        let input: SourceListInput = try #require(runtime.listInputs.first)
        #expect(input.page == 3)
        #expect(input.urlOverride == nil)
        #expect(input.context.sourceID == "user.example")
        #expect(input.context.operation == .list)
        #expect(input.context.pageID == "home")
        #expect(input.context.tabID == "latest")
        #expect(input.context.sectionID == "main-grid")
        #expect(input.context.sectionRole == "category")
        #expect(input.context.ruleID == "latest-list")
        #expect(input.context.debugMode == true)
    }

    @Test func sourceDefinitionMapperMapsOwnershipRuleMetadataAndBaseURLFallback() throws {
        let mapper: SourceDefinitionMapper = SourceDefinitionMapper()
        let builtInSource: Source = try Self.source(id: "built-in.example")
        let userSource: Source = try Self.source(id: "user.example")
        var invalidBaseURLSource: Source = userSource
        invalidBaseURLSource.baseURL = "   "

        let builtInDefinition: SourceDefinition = mapper.definition(from: builtInSource)
        let userDefinition: SourceDefinition = mapper.definition(from: userSource)
        let fallbackDefinition: SourceDefinition = mapper.definition(from: invalidBaseURLSource)

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

    @Test func outputMapperMapsItemsChaptersReaderAndPassesDiagnosticsThrough() throws {
        let mapper: SourceRuntimeOutputMapper = SourceRuntimeOutputMapper()
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
        let listOutput: SourceListOutput = mapper.listOutput(
            items: [item],
            pagination: pagination,
            diagnostics: diagnostics
        )
        let detailOutput: SourceDetailOutput = mapper.detailOutput(
            chapters: [
                ChapterLink(title: "第01话", url: "https://example.test/chapters/1"),
                ChapterLink(title: "invalid", url: "   ")
            ],
            diagnostics: diagnostics
        )
        let readerOutput: SourceReaderOutput = mapper.readerOutput(
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

private struct StubSourceRuntime: SourceRuntime {
    let definition: SourceDefinition

    var capabilities: SourceRuntimeCapabilities {
        return SourceRuntimeCapabilities(
            supportsSearch: true,
            supportsPagination: true,
            supportsDetail: true,
            supportsReader: true,
            supportsDebug: false,
            supportsCandidateAnalysis: false,
            requiresWebView: false,
            requiresCookieStore: false,
            requiresAccount: false
        )
    }

    func loadList(_ input: SourceListInput) async throws -> SourceListOutput {
        return SourceListOutput(
            items: [],
            pagination: nil,
            diagnostics: SourceRuntimeDiagnostics.skipped(message: "Stub runtime.")
        )
    }

    func search(_ input: SourceSearchInput) async throws -> SourceListOutput {
        return SourceListOutput(
            items: [],
            pagination: nil,
            diagnostics: SourceRuntimeDiagnostics.skipped(message: "Stub runtime.")
        )
    }

    func loadDetail(_ input: SourceDetailInput) async throws -> SourceDetailOutput {
        return SourceDetailOutput(
            chapters: [],
            diagnostics: SourceRuntimeDiagnostics.skipped(message: "Stub runtime.")
        )
    }

    func loadReader(_ input: SourceReaderInput) async throws -> SourceReaderOutput {
        return SourceReaderOutput(
            chapter: SourceReaderChapter(title: nil, imageURLs: []),
            diagnostics: SourceRuntimeDiagnostics.skipped(message: "Stub runtime.")
        )
    }

    func debug(_ input: SourceRuntimeContext) async throws -> SourceDebugOutput {
        return SourceDebugOutput(
            diagnostics: SourceRuntimeDiagnostics.skipped(message: "Stub runtime.")
        )
    }
}

private final class RecordingSourceRuntime: SourceRuntime {
    let definition: SourceDefinition
    private(set) var listInputs: [SourceListInput] = []

    init(definition: SourceDefinition) {
        self.definition = definition
    }

    var capabilities: SourceRuntimeCapabilities {
        return SourceRuntimeCapabilities(
            supportsSearch: false,
            supportsPagination: false,
            supportsDetail: false,
            supportsReader: false,
            supportsDebug: false,
            supportsCandidateAnalysis: false,
            requiresWebView: false,
            requiresCookieStore: false,
            requiresAccount: false
        )
    }

    func loadList(_ input: SourceListInput) async throws -> SourceListOutput {
        self.listInputs.append(input)

        return SourceListOutput(
            items: [],
            pagination: nil,
            diagnostics: SourceRuntimeDiagnostics.succeeded()
        )
    }

    func search(_ input: SourceSearchInput) async throws -> SourceListOutput {
        return SourceListOutput(
            items: [],
            pagination: nil,
            diagnostics: SourceRuntimeDiagnostics.skipped(message: "Stub runtime.")
        )
    }

    func loadDetail(_ input: SourceDetailInput) async throws -> SourceDetailOutput {
        return SourceDetailOutput(
            chapters: [],
            diagnostics: SourceRuntimeDiagnostics.skipped(message: "Stub runtime.")
        )
    }

    func loadReader(_ input: SourceReaderInput) async throws -> SourceReaderOutput {
        return SourceReaderOutput(
            chapter: SourceReaderChapter(title: nil, imageURLs: []),
            diagnostics: SourceRuntimeDiagnostics.skipped(message: "Stub runtime.")
        )
    }

    func debug(_ input: SourceRuntimeContext) async throws -> SourceDebugOutput {
        return SourceDebugOutput(
            diagnostics: SourceRuntimeDiagnostics.skipped(message: "Stub runtime.")
        )
    }
}
