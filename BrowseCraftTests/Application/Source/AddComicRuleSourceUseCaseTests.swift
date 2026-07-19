import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft

struct AddComicRuleSourceUseCaseTests {
    @Test func savesComicSourceAfterRuntimeListLoadSucceeds() async throws {
        let repository: ComicRuleInMemorySourceRepository = ComicRuleInMemorySourceRepository()
        let runtimeRegistry: AddComicRuntimeRegistry = AddComicRuntimeRegistry()
        let useCase: AddComicRuleSourceUseCase = AddComicRuleSourceUseCase(
            sourceRepository: repository,
            refreshSourceRuntimeUseCase: runtimeRegistry.refreshUseCase()
        )

        let result: AddComicRuleSourceResult = try await useCase.execute(
            name: "Comic Example",
            baseURL: "https://comic.example.test",
            ruleJSON: SiteRule.exampleJSON
        )
        let source: Source = result.source

        #expect(source.name == "Comic Example")
        #expect(source.baseURL == "https://comic.example.test")
        #expect(repository.savedSources[source.id] == source)
        #expect(runtimeRegistry.runtimes.first?.listInputs.count == 1)
        #expect(result.listOutput.items.count == 1)
    }

    @Test func doesNotSaveComicSourceWhenRuntimeListLoadFails() async throws {
        let repository: ComicRuleInMemorySourceRepository = ComicRuleInMemorySourceRepository()
        let runtimeRegistry: AddComicRuntimeRegistry = AddComicRuntimeRegistry(
            loadError: AddComicRuntimeTestError.listLoadFailed
        )
        let useCase: AddComicRuleSourceUseCase = AddComicRuleSourceUseCase(
            sourceRepository: repository,
            refreshSourceRuntimeUseCase: runtimeRegistry.refreshUseCase()
        )

        await #expect(throws: AddComicRuntimeTestError.listLoadFailed) {
            _ = try await useCase.execute(
                name: "Comic Example",
                baseURL: "https://comic.example.test",
                ruleJSON: SiteRule.exampleJSON
            )
        }

        #expect(repository.savedSources.isEmpty)
        #expect(runtimeRegistry.runtimes.first?.listInputs.count == 1)
    }

    @Test func doesNotSaveComicSourceWhenRuntimeListIsEmpty() async throws {
        let repository: ComicRuleInMemorySourceRepository = ComicRuleInMemorySourceRepository()
        let runtimeRegistry: AddComicRuntimeRegistry = AddComicRuntimeRegistry(outputItemCount: 0)
        let useCase: AddComicRuleSourceUseCase = AddComicRuleSourceUseCase(
            sourceRepository: repository,
            refreshSourceRuntimeUseCase: runtimeRegistry.refreshUseCase()
        )

        await #expect(throws: SourceListLoadValidationError.emptyList) {
            _ = try await useCase.execute(
                name: "Comic Example",
                baseURL: "https://comic.example.test",
                ruleJSON: SiteRule.exampleJSON
            )
        }

        #expect(repository.savedSources.isEmpty)
        #expect(runtimeRegistry.runtimes.first?.listInputs.count == 1)
    }
}

private enum AddComicRuntimeTestError: Error, Equatable {
    case listLoadFailed
}

private final class ComicRuleInMemorySourceRepository: SourceRepository {
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

private final class AddComicRuntimeRegistry {
    private let loadError: Error?
    private let outputItemCount: Int
    private(set) var runtimes: [AddComicRecordingRuntime] = []

    init(loadError: Error? = nil, outputItemCount: Int = 1) {
        self.loadError = loadError
        self.outputItemCount = outputItemCount
    }

    func refreshUseCase() -> RefreshSourceRuntimeUseCase {
        return RefreshSourceRuntimeUseCase(
            runtimeResolver: TestSourceRuntimeResolver { source in
                let runtime: AddComicRecordingRuntime = AddComicRecordingRuntime(
                    definition: SourceDefinitionMapper().definition(from: source),
                    loadError: self.loadError,
                    outputItemCount: self.outputItemCount
                )
                self.runtimes.append(runtime)
                return runtime
            }
        )
    }
}

private final class AddComicRecordingRuntime: SourceRuntime {
    let definition: SourceDefinition
    private let loadError: Error?
    private let outputItemCount: Int
    private(set) var listInputs: [SourceListInput] = []

    init(definition: SourceDefinition, loadError: Error?, outputItemCount: Int) {
        self.definition = definition
        self.loadError = loadError
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
        if let loadError: Error {
            throw loadError
        }

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
                id: "comic.item.\(index)",
                title: "Comic Item \(index)",
                detailURL: nil,
                coverURL: nil,
                latestText: nil,
                updatedAt: nil
            )
        }
    }
}
