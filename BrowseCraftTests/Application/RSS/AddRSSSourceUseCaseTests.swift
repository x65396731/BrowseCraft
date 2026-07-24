import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft

// 中文注释：AddRSSSourceUseCaseTests 固定 P4.9.5 RSS Source 保存入口和公开 feed 边界。
struct AddRSSSourceUseCaseTests {
    @Test func savesRSSSourceConfigurationUsingFeedTitle() async throws {
        let repository: RSSInMemorySourceRepository = RSSInMemorySourceRepository()
        let runtimeRegistry: AddRSSRuntimeRegistry = AddRSSRuntimeRegistry()
        let useCase: AddRSSSourceUseCase = AddRSSSourceUseCase(
            sourceRepository: repository,
            feedLoader: AddRSSStubFeedLoader(
                feed: BrowseCraft.RSSFeed(title: "Solidot", items: [])
            ),
            refreshSourceRuntimeUseCase: runtimeRegistry.refreshUseCase(),
            now: { Date(timeIntervalSince1970: 1_000) },
            makeID: { "rss.solidot" }
        )

        let result: AddRSSSourceResult = try await useCase.execute(
            feedURLString: " https://www.solidot.org/index.rss "
        )
        let source: Source = result.source

        #expect(source.id == "rss.solidot")
        #expect(source.name == "Solidot")
        #expect(source.baseURL == "https://www.solidot.org")
        #expect(source.type == .rss)
        #expect(source.enabled == true)
        #expect(source.createdAt == Date(timeIntervalSince1970: 1_000))
        #expect(repository.savedSources[source.id] == source)
        #expect(runtimeRegistry.runtimes.first?.listInputs.count == 1)
        #expect(result.listOutput.items.count == 1)

        guard case .rss(let configuration) = source.configuration else {
            Issue.record("Expected rss configuration.")
            return
        }

        #expect(configuration.definition.feedURL.absoluteString == "https://www.solidot.org/index.rss")
        #expect(configuration.definition.requiresAccount == false)
        #expect(configuration.definition.refreshPolicy == .manual)
    }

    @Test func inputNameOverridesFeedTitleAndSourceRecordRoundTripsRSSConfiguration() async throws {
        let repository: RSSInMemorySourceRepository = RSSInMemorySourceRepository()
        let runtimeRegistry: AddRSSRuntimeRegistry = AddRSSRuntimeRegistry()
        let useCase: AddRSSSourceUseCase = AddRSSSourceUseCase(
            sourceRepository: repository,
            feedLoader: AddRSSStubFeedLoader(feed: BrowseCraft.RSSFeed(title: "Solidot", items: [])),
            refreshSourceRuntimeUseCase: runtimeRegistry.refreshUseCase(),
            now: { Date(timeIntervalSince1970: 2_000) },
            makeID: { "rss.custom" }
        )

        let result: AddRSSSourceResult = try await useCase.execute(
            feedURLString: "https://www.solidot.org/index.rss",
            name: "My Feed"
        )
        let source: Source = result.source
        let record: SourceRecord = try SourceRecord(source: source)
        let decodedSource: Source = try record.domainModel()

        #expect(source.name == "My Feed")
        #expect(record.kind == "rss")
        #expect(record.configJSON.contains("https:\\/\\/www.solidot.org\\/index.rss"))
        #expect(decodedSource.configuration == source.configuration)
    }

    @Test func rejectsInvalidFeedURL() async throws {
        let useCase: AddRSSSourceUseCase = AddRSSSourceUseCase(
            sourceRepository: RSSInMemorySourceRepository(),
            feedLoader: AddRSSStubFeedLoader(feed: BrowseCraft.RSSFeed(title: nil, items: [])),
            refreshSourceRuntimeUseCase: AddRSSRuntimeRegistry().refreshUseCase()
        )

        await #expect(throws: AddRSSSourceError.invalidFeedURL) {
            _ = try await useCase.execute(feedURLString: "not a url")
        }
    }

    @Test func doesNotSaveRSSSourceWhenRuntimeListIsEmpty() async throws {
        let repository: RSSInMemorySourceRepository = RSSInMemorySourceRepository()
        let runtimeRegistry: AddRSSRuntimeRegistry = AddRSSRuntimeRegistry(outputItemCount: 0)
        let useCase: AddRSSSourceUseCase = AddRSSSourceUseCase(
            sourceRepository: repository,
            feedLoader: AddRSSStubFeedLoader(feed: BrowseCraft.RSSFeed(title: "Empty Feed", items: [])),
            refreshSourceRuntimeUseCase: runtimeRegistry.refreshUseCase()
        )

        await #expect(throws: SourceListLoadValidationError.emptyList) {
            _ = try await useCase.execute(feedURLString: "https://www.solidot.org/index.rss")
        }

        #expect(repository.savedSources.isEmpty)
        #expect(runtimeRegistry.runtimes.first?.listInputs.count == 1)
    }
}

private final class RSSInMemorySourceRepository: SourceRepository {
    var savedSources: [String: Source] = [:]

    func fetchSources() throws -> [Source] {
        return Array(self.savedSources.values)
    }

    func saveSource(_ source: Source) throws {
        self.savedSources[source.id] = source
    }

    func deleteSource(id: String) throws {
        self.savedSources.removeValue(forKey: id)
    }
}

private struct AddRSSStubFeedLoader: RSSFeedLoading {
    var feed: BrowseCraft.RSSFeed

    func load(feedURL: URL) async throws -> BrowseCraft.RSSFeed {
        return self.feed
    }
}

private final class AddRSSRuntimeRegistry {
    private let outputItemCount: Int
    private(set) var runtimes: [AddRSSRecordingRuntime] = []

    init(outputItemCount: Int = 1) {
        self.outputItemCount = outputItemCount
    }

    func refreshUseCase() -> RefreshSourceRuntimeUseCase {
        return RefreshSourceRuntimeUseCase(
            runtimeResolver: TestSourceRuntimeResolver(
                rssRuntimeFactory: { definition in
                    let runtime: AddRSSRecordingRuntime = AddRSSRecordingRuntime(
                        definition: definition,
                        outputItemCount: self.outputItemCount
                    )
                    self.runtimes.append(runtime)
                    return runtime
                },
                comicRuntimeFactory: { source in
                    return AddRSSRecordingRuntime(
                        definition: SourceDefinitionMapper().definition(from: source),
                        outputItemCount: self.outputItemCount
                    )
                }
            )
        )
    }
}

private final class AddRSSRecordingRuntime: SourceRuntime {
    let definition: SourceDefinition
    private let outputItemCount: Int
    private(set) var listInputs: [SourceListInput] = []

    init(definition: SourceDefinition, outputItemCount: Int) {
        self.definition = definition
        self.outputItemCount = outputItemCount
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
            items: Self.items(count: self.outputItemCount),
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

    private static func items(count: Int) -> [SourceContentItem] {
        return (0..<count).map { index in
            SourceContentItem(
                id: "rss.item.\(index)",
                title: "RSS Item \(index)",
                detailURL: nil,
                coverURL: nil,
                latestText: nil,
                updatedAt: nil
            )
        }
    }
}
