import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft
import BrowseCraftDomain

/// 来源内搜索（`BC-SEARCH-007` App 侧）：能力由 runtime 声明；结果与列表同型进入 searchResults；失败给用户文案。
@MainActor
struct LibraryViewModelSearchTests {
    private typealias Harness = ViewModelTestHarness

    private static func makeViewModel(
        database: AppDatabase,
        source: Source,
        runtime: ScriptedSourceRuntime
    ) -> LibraryViewModel {
        let resolver: TestSourceRuntimeResolver = Harness.resolver([source.id: runtime])
        let sourceRepository: SourceRepository = GRDBSourceRepository(database: database)
        let favoriteRepository: FavoriteRepository = GRDBFavoriteRepository(database: database)
        let userLibraryStateRepository: UserLibraryStateRepository = GRDBUserLibraryStateRepository(database: database)
        return LibraryViewModel(
            persistenceCoordinator: LibraryPersistenceCoordinator(
                syncBuiltInSourcesUseCase: SyncBuiltInSourcesUseCase(sourceRepository: sourceRepository),
                reconcileSourceSlotAssignmentsUseCase: ReconcileSourceSlotAssignmentsUseCase(
                    sourceRepository: sourceRepository
                ),
                toggleFavoriteUseCase: ToggleFavoriteUseCase(favoriteRepository: favoriteRepository),
                loadUserLibraryStateUseCase: LoadUserLibraryStateUseCase(repository: userLibraryStateRepository),
                saveUserLibraryStateUseCase: SaveUserLibraryStateUseCase(repository: userLibraryStateRepository)
            ),
            refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase(runtimeResolver: resolver),
            resolveLibrarySourcePresentationUseCase: ResolveLibrarySourcePresentationUseCase(),
            sourceCredentialStore: InMemorySourceCredentialStore(),
            sourceSelectionStore: SourceSelectionStore(),
            searchSourceContentUseCase: SearchSourceContentUseCase(runtimeResolver: resolver),
            now: { Harness.fixedNow }
        )
    }

    @Test func searchIsHiddenUntilTheRuntimeDeclaresIt() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let source: Source = try Harness.makeComicSource()
        try GRDBSourceRepository(database: database).saveSource(source)
        let runtime: ScriptedSourceRuntime = ScriptedSourceRuntime(source: source, list: { _ in
            ScriptedSourceRuntime.listOutput(ids: ["a"])
        })
        let viewModel: LibraryViewModel = Self.makeViewModel(database: database, source: source, runtime: runtime)
        _ = await viewModel.loadIfNeeded()

        #expect(viewModel.selectedSourceSupportsSearch == false)
        viewModel.presentSearch()
        #expect(viewModel.isPresentingSearch == false)

        runtime.supportsSearch = true
        #expect(viewModel.selectedSourceSupportsSearch)
        viewModel.presentSearch()
        #expect(viewModel.isPresentingSearch)
        viewModel.dismissSearch()
        #expect(viewModel.isPresentingSearch == false)
    }

    @Test func performSearchMapsResultsLikeAListAndRecordsTheKeyword() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let source: Source = try Harness.makeComicSource()
        try GRDBSourceRepository(database: database).saveSource(source)
        let runtime: ScriptedSourceRuntime = ScriptedSourceRuntime(source: source, list: { _ in
            ScriptedSourceRuntime.listOutput(ids: ["a"])
        })
        runtime.supportsSearch = true
        runtime.setSearchHandler { input in
            ScriptedSourceRuntime.listOutput(ids: ["hit-\(input.keyword)"])
        }
        let viewModel: LibraryViewModel = Self.makeViewModel(database: database, source: source, runtime: runtime)
        _ = await viewModel.loadIfNeeded()

        viewModel.searchKeyword = "  海贼王 "
        await viewModel.performSearch()

        #expect(runtime.searchInputs.map(\.keyword) == ["海贼王"])
        #expect(runtime.searchInputs.first?.context.operation == .search)
        #expect(viewModel.searchResults.map(\.id) == ["hit-海贼王"])
        #expect(viewModel.searchResults.allSatisfy { item in item.sourceId == source.id })
        #expect(viewModel.hasSearched)
        #expect(viewModel.searchErrorMessage == nil)
        // 中文注释：搜索不改动库页列表。
        #expect(viewModel.items.map(\.id) == ["a"])
    }

    @Test func emptyKeywordDoesNotHitTheRuntimeAndFailureBecomesAMessage() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let source: Source = try Harness.makeComicSource()
        try GRDBSourceRepository(database: database).saveSource(source)
        let runtime: ScriptedSourceRuntime = ScriptedSourceRuntime(source: source, list: { _ in
            ScriptedSourceRuntime.listOutput(ids: ["a"])
        })
        runtime.supportsSearch = true
        runtime.setSearchHandler { _ in
            throw URLError(.notConnectedToInternet)
        }
        let viewModel: LibraryViewModel = Self.makeViewModel(database: database, source: source, runtime: runtime)
        _ = await viewModel.loadIfNeeded()

        viewModel.searchKeyword = "   "
        await viewModel.performSearch()
        #expect(runtime.searchInputs.isEmpty)
        #expect(viewModel.hasSearched == false)

        viewModel.searchKeyword = "x"
        await viewModel.performSearch()
        #expect(runtime.searchInputs.count == 1)
        #expect(viewModel.searchResults.isEmpty)
        #expect(viewModel.searchErrorMessage != nil)
        #expect(viewModel.isSearching == false)
    }
}
