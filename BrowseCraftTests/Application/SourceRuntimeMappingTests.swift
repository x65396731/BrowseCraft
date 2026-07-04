import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft

// 中文注释：P3 runtime 本地映射合同测试，防止 Core runtime 字段扩展后 App 侧映射静默丢字段。
struct SourceRuntimeMappingTests {
    @Test func sourceRuntimeResolverReturnsRuleRuntimeFromSourceDefinitionKind() throws {
        var source: Source = try Self.source(id: "user.example")
        source.type = .rss
        let resolver = SourceRuntimeResolver { source in
            return StubSourceRuntime(definition: SourceDefinitionMapper().definition(from: source))
        }

        let runtime: any SourceRuntime = try resolver.runtime(for: source)

        #expect(runtime.definition.id == "user.example")
        #expect(runtime.definition.kind == .rule)
        #expect(runtime.capabilities.supportsReader)
    }

    @Test func sourceRuntimeResolverRejectsRSSAndPluginDefinitionsUntilRuntimesAreConnected() throws {
        let resolver = SourceRuntimeResolver { source in
            return StubSourceRuntime(definition: SourceDefinitionMapper().definition(from: source))
        }
        let rssDefinition: SourceDefinition = SourceDefinitionMapper().definition(
            id: "rss.example",
            name: "RSS Example",
            baseURL: "https://example.test",
            version: nil,
            ownership: .user,
            configuration: .rss(
                RSSSourceConfiguration(
                    definition: RSSSourceDefinition(
                        feedURL: try #require(URL(string: "https://example.test/feed.xml")),
                        requiresAccount: false,
                        refreshPolicy: .manual
                    )
                )
            )
        )
        let pluginDefinition: SourceDefinition = SourceDefinitionMapper().definition(
            id: "plugin.example",
            name: "Plugin Example",
            baseURL: "https://plugin.example",
            version: 1,
            ownership: .imported,
            configuration: .plugin(
                PluginSourceConfiguration(
                    definition: PluginSourceDefinition(
                        id: "plugin.example",
                        manifestVersion: 1,
                        displayName: "Plugin Example",
                        runtime: .javaScript,
                        entrypoint: "index.js",
                        permissions: [.network],
                        checksum: "checksum",
                        isExecutable: false,
                        disabledReason: "P3-8 does not execute plugins."
                    )
                )
            )
        )

        do {
            _ = try resolver.runtime(for: rssDefinition)
            Issue.record("Expected RSS runtime resolution to fail until P3-9.")
        } catch SourceRuntimeError.unsupported(.custom(let message)) {
            #expect(message.contains("P3-9"))
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }

        do {
            _ = try resolver.runtime(for: pluginDefinition)
            Issue.record("Expected plugin runtime resolution to fail until P3-10.")
        } catch SourceRuntimeError.unsupported(.custom(let message)) {
            #expect(message.contains("P3-10"))
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }
    }

    @Test func architectureGuardKeepsRuntimeSlotsIndependentFromSiteRulePayload() throws {
        let resolver = SourceRuntimeResolver(
            rssRuntimeFactory: { definition in
                return StubSourceRuntime(definition: definition)
            },
            pluginRuntimeFactory: { definition in
                return StubSourceRuntime(definition: definition)
            },
            ruleRuntimeFactory: { source in
                return StubSourceRuntime(definition: SourceDefinitionMapper().definition(from: source))
            }
        )
        let mapper = SourceDefinitionMapper()
        let rssDefinition = mapper.definition(
            id: "rss.example",
            name: "RSS Example",
            baseURL: "https://example.test",
            version: nil,
            ownership: .user,
            configuration: .rss(
                RSSSourceConfiguration(
                    definition: RSSSourceDefinition(
                        feedURL: try #require(URL(string: "https://example.test/feed.xml")),
                        requiresAccount: false,
                        refreshPolicy: .manual
                    )
                )
            )
        )
        let pluginDefinition = mapper.definition(
            id: "plugin.example",
            name: "Plugin Example",
            baseURL: "https://plugin.example",
            version: 1,
            ownership: .imported,
            configuration: .plugin(
                PluginSourceConfiguration(
                    definition: PluginSourceDefinition(
                        id: "plugin.example",
                        manifestVersion: 1,
                        displayName: "Plugin Example",
                        runtime: .javaScript,
                        entrypoint: "index.js",
                        permissions: [.network],
                        checksum: "checksum",
                        isExecutable: false,
                        disabledReason: "P3-8 does not execute plugins."
                    )
                )
            )
        )
        let ruleDefinition = mapper.definition(from: try Self.source(id: "rule.example"))

        let rssRuntime: any SourceRuntime = try resolver.runtime(for: rssDefinition)
        let pluginRuntime: any SourceRuntime = try resolver.runtime(for: pluginDefinition)

        #expect(rssRuntime.definition.kind == .rss)
        #expect(rssRuntime.definition.rule == nil)
        #expect(rssRuntime.definition.rss?.feedURL.absoluteString == "https://example.test/feed.xml")
        #expect(pluginRuntime.definition.kind == .plugin)
        #expect(pluginRuntime.definition.rule == nil)
        #expect(pluginRuntime.definition.plugin?.entrypoint == "index.js")

        do {
            _ = try resolver.runtime(for: ruleDefinition)
            Issue.record("Expected rule definition without App Source payload to fail.")
        } catch SourceRuntimeError.invalidInput(let message) {
            #expect(message.contains("App Source payload"))
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

    @Test func sourceDefinitionMapperMapsRuntimeSpecificConfigurationsWithoutRuleFallback() throws {
        let mapper: SourceDefinitionMapper = SourceDefinitionMapper()
        let rssDefinition: SourceDefinition = mapper.definition(
            id: "rss.example",
            name: "RSS Example",
            baseURL: "https://example.test",
            version: nil,
            ownership: .user,
            configuration: .rss(
                RSSSourceConfiguration(
                    definition: RSSSourceDefinition(
                        feedURL: try #require(URL(string: "https://example.test/feed.xml")),
                        requiresAccount: false,
                        refreshPolicy: .manual
                    )
                )
            )
        )
        let pluginDefinition: SourceDefinition = mapper.definition(
            id: "plugin.example",
            name: "Plugin Example",
            baseURL: "https://plugin.example",
            version: 1,
            ownership: .imported,
            configuration: .plugin(
                PluginSourceConfiguration(
                    definition: PluginSourceDefinition(
                        id: "plugin.example",
                        manifestVersion: 1,
                        displayName: "Plugin Example",
                        runtime: .javaScript,
                        entrypoint: "index.js",
                        permissions: [.network],
                        checksum: "checksum",
                        isExecutable: false,
                        disabledReason: "P3-8 does not execute plugins."
                    )
                )
            )
        )

        #expect(rssDefinition.kind == .rss)
        #expect(rssDefinition.rule == nil)
        #expect(rssDefinition.rss?.feedURL.absoluteString == "https://example.test/feed.xml")
        #expect(rssDefinition.rss?.requiresAccount == false)
        #expect(rssDefinition.rss?.refreshPolicy == .manual)
        #expect(rssDefinition.plugin == nil)

        #expect(pluginDefinition.kind == .plugin)
        #expect(pluginDefinition.rule == nil)
        #expect(pluginDefinition.rss == nil)
        #expect(pluginDefinition.plugin?.id == "plugin.example")
        #expect(pluginDefinition.plugin?.entrypoint == "index.js")
        #expect(pluginDefinition.plugin?.isExecutable == false)
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

    @Test func ruleSourceItemReferenceMapperMapsDetailHandoffWithoutReaderReplacement() throws {
        let mapper = RuleSourceItemReferenceMapper()
        let runtimeContext = SourceRuntimeContext(
            sourceID: "user.example",
            pageID: "home",
            tabID: "latest",
            sectionID: "main-grid",
            sectionRole: "main",
            ruleID: "latest-list",
            requestOverride: nil,
            debugMode: false,
            operation: .detail
        )
        let item = ContentItem(
            id: "item-1",
            sourceId: "user.example",
            title: "Title",
            detailURL: "https://example.test/comics/1",
            coverURL: "   ",
            type: .comic,
            latestText: "第01话",
            listContext: ListContext(
                pageId: "home",
                tabId: "latest",
                sectionId: "main-grid",
                listRuleId: "latest-list",
                sectionRole: .main
            )
        )

        let reference: SourceItemReference = mapper.reference(
            from: item,
            runtimeContext: runtimeContext
        )

        #expect(reference.id == "item-1")
        #expect(reference.sourceID == "user.example")
        #expect(reference.title == "Title")
        #expect(reference.contentType == .comic)
        #expect(reference.detailURL?.absoluteString == "https://example.test/comics/1")
        #expect(reference.chapterURL == nil)
        #expect(reference.coverURL == nil)
        #expect(reference.latestText == "第01话")
        #expect(reference.listContext?.pageID == "home")
        #expect(reference.listContext?.tabID == "latest")
        #expect(reference.listContext?.sectionID == "main-grid")
        #expect(reference.listContext?.sectionRole == "main")
        #expect(reference.listContext?.ruleID == "latest-list")
        #expect(reference.handoffIntent == .detail)
        #expect(reference.runtimeContext == runtimeContext)
    }

    @Test func ruleSourceItemReferenceMapperMapsDirectReaderChapterHandoff() throws {
        let mapper = RuleSourceItemReferenceMapper()
        let requestOverride = SourceRequestOverride(
            url: URL(string: "https://example.test/read/1")!,
            headers: ["Referer": "https://example.test"],
            method: "GET"
        )
        let item = ContentItem(
            id: "item-1",
            sourceId: "user.example",
            title: "Title",
            detailURL: "https://example.test/comics/1",
            coverURL: "https://example.test/covers/1.jpg",
            type: .comic,
            latestText: nil
        )
        let chapter = ChapterLink(
            title: "第01话",
            url: "https://example.test/chapters/1"
        )

        let reference: SourceItemReference = mapper.reference(
            from: item,
            handoffIntent: .directReader,
            chapter: chapter,
            requestOverride: requestOverride
        )

        #expect(reference.handoffIntent == .directReader)
        #expect(reference.detailURL?.absoluteString == "https://example.test/comics/1")
        #expect(reference.chapterURL?.absoluteString == "https://example.test/chapters/1")
        #expect(reference.coverURL?.absoluteString == "https://example.test/covers/1.jpg")
        #expect(reference.requestOverride == requestOverride)
        #expect(reference.runtimeContext == nil)
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
