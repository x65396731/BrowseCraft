import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft
import BrowseCraftDomain

// 中文注释：LibraryViewModel 状态机测试——真实 GRDB 持久化 + 脚本 runtime，
// 覆盖首次加载、失败、收藏、状态恢复、Tab 切换和跨页面 source 切换。
@MainActor
struct LibraryViewModelTests {
    private typealias Harness = ViewModelTestHarness

    @Test func loadWithoutSourcesReportsNoSources() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let viewModel: LibraryViewModel = Harness.makeLibraryViewModel(
            database: database,
            resolver: Harness.resolver()
        )

        let outcome: LibraryInitialLoadOutcome = await viewModel.loadIfNeeded()

        #expect(outcome == .noSources)
        #expect(viewModel.sources.isEmpty)
        #expect(viewModel.items.isEmpty)
        #expect(viewModel.selectedSourceID == nil)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func loadSelectsSourceRefreshesAndPersistsState() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let source: Source = try Harness.makeComicSource()
        try GRDBSourceRepository(database: database).saveSource(source)
        let runtime: ScriptedSourceRuntime = ScriptedSourceRuntime(source: source, list: { _ in
            ScriptedSourceRuntime.listOutput(ids: ["a", "b"])
        })
        let store: SourceSelectionStore = SourceSelectionStore()
        let viewModel: LibraryViewModel = Harness.makeLibraryViewModel(
            database: database,
            resolver: Harness.resolver([source.id: runtime]),
            selectionStore: store
        )

        let outcome: LibraryInitialLoadOutcome = await viewModel.loadIfNeeded()

        #expect(outcome == .loaded)
        #expect(viewModel.selectedSourceID == source.id)
        #expect(store.selectedSourceID == source.id)
        #expect(viewModel.items.map(\.id) == ["a", "b"])
        #expect(viewModel.items.allSatisfy { item in item.sourceId == source.id && item.type == .comic })
        #expect(viewModel.isRefreshing == false)
        #expect(viewModel.selectedListTabErrorMessage == nil)
        #expect(runtime.listInputs.count == 1)
        #expect(runtime.listInputs.first?.context.sourceID == source.id)
        #expect(runtime.listInputs.first?.page == 1)
        #expect(store.preparedLibrarySnapshot?.items.map(\.id) == ["a", "b"])

        let stateRepository: GRDBUserLibraryStateRepository = GRDBUserLibraryStateRepository(database: database)
        let persisted: Bool = await Harness.waitUntil {
            let state: UserLibraryState? = try? stateRepository.fetch(userID: AppUser.localDefaultID)
            return state?.selectedSourceID == source.id && state?.lastRefreshAt != nil
        }
        #expect(persisted)
    }

    @Test func runtimeFailureIsShownOnTheSelectedTab() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let source: Source = try Harness.makeComicSource()
        try GRDBSourceRepository(database: database).saveSource(source)
        let runtime: ScriptedSourceRuntime = ScriptedSourceRuntime(source: source, list: { _ in
            throw TestPortError(reason: "site down")
        })
        let viewModel: LibraryViewModel = Harness.makeLibraryViewModel(
            database: database,
            resolver: Harness.resolver([source.id: runtime])
        )

        let outcome: LibraryInitialLoadOutcome = await viewModel.loadIfNeeded()

        #expect(outcome == .failed)
        #expect(viewModel.items.isEmpty)
        #expect(viewModel.selectedListTabErrorMessage != nil)
        #expect(viewModel.isRefreshing == false)
        #expect(viewModel.selectedSourceID == source.id)
    }

    @Test func loadIfNeededSharesASingleOutcome() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let source: Source = try Harness.makeComicSource()
        try GRDBSourceRepository(database: database).saveSource(source)
        let runtime: ScriptedSourceRuntime = ScriptedSourceRuntime(source: source, list: { _ in
            ScriptedSourceRuntime.listOutput(ids: ["a"])
        })
        let viewModel: LibraryViewModel = Harness.makeLibraryViewModel(
            database: database,
            resolver: Harness.resolver([source.id: runtime])
        )

        async let first: LibraryInitialLoadOutcome = viewModel.loadIfNeeded()
        async let second: LibraryInitialLoadOutcome = viewModel.loadIfNeeded()
        let outcomes: [LibraryInitialLoadOutcome] = await [first, second]
        let third: LibraryInitialLoadOutcome = await viewModel.loadIfNeeded()

        #expect(outcomes == [.loaded, .loaded])
        #expect(third == .loaded)
        #expect(runtime.listInputs.count == 1)
    }

    @Test func toggleFavoriteRoundTripsThroughRepository() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let source: Source = try Harness.makeComicSource()
        try GRDBSourceRepository(database: database).saveSource(source)
        let runtime: ScriptedSourceRuntime = ScriptedSourceRuntime(source: source, list: { _ in
            ScriptedSourceRuntime.listOutput(ids: ["a", "b"])
        })
        let viewModel: LibraryViewModel = Harness.makeLibraryViewModel(
            database: database,
            resolver: Harness.resolver([source.id: runtime])
        )
        _ = await viewModel.loadIfNeeded()
        let item: ContentItem = try #require(viewModel.items.first)
        let favoriteRepository: GRDBFavoriteRepository = GRDBFavoriteRepository(database: database)

        await viewModel.toggleFavorite(item: item)

        #expect(viewModel.favoriteItemIDs.contains(item.id))
        #expect(try favoriteRepository.fetchFavoriteItemIDs(sourceID: source.id).contains(item.id))

        await viewModel.toggleFavorite(item: item)

        #expect(viewModel.favoriteItemIDs.contains(item.id) == false)
        #expect(try favoriteRepository.fetchFavoriteItemIDs(sourceID: source.id).isEmpty)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func persistedLibraryStateRestoresTheSelectedSource() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let comic: Source = try Harness.makeComicSource(id: "built-in.comic")
        let custom: Source = try Harness.makeComicSource(id: "comic.custom")
        let sourceRepository: GRDBSourceRepository = GRDBSourceRepository(database: database)
        try sourceRepository.saveSource(comic)
        try sourceRepository.saveSource(custom)
        try GRDBUserLibraryStateRepository(database: database).save(
            UserLibraryState(
                userID: AppUser.localDefaultID,
                selectedSourceID: custom.id,
                listContext: nil,
                lastRefreshAt: nil,
                updatedAt: Harness.fixedNow
            )
        )
        let comicRuntime: ScriptedSourceRuntime = ScriptedSourceRuntime(source: comic)
        let customRuntime: ScriptedSourceRuntime = ScriptedSourceRuntime(source: custom, list: { _ in
            ScriptedSourceRuntime.listOutput(ids: ["custom-1"])
        })
        let viewModel: LibraryViewModel = Harness.makeLibraryViewModel(
            database: database,
            resolver: Harness.resolver([comic.id: comicRuntime, custom.id: customRuntime])
        )

        let outcome: LibraryInitialLoadOutcome = await viewModel.loadIfNeeded()

        #expect(outcome == .loaded)
        #expect(viewModel.selectedSourceID == custom.id)
        #expect(viewModel.items.map(\.id) == ["custom-1"])
        #expect(viewModel.items.first?.type == .comic)
        #expect(customRuntime.listInputs.count == 1)
        #expect(comicRuntime.listInputs.isEmpty)
    }

    @Test func selectingAnotherTabRefreshesWithThatTabContext() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let source: Source = try Harness.makeComicSource()
        try GRDBSourceRepository(database: database).saveSource(source)
        let runtime: ScriptedSourceRuntime = ScriptedSourceRuntime(source: source, list: { input in
            ScriptedSourceRuntime.listOutput(ids: ["\(input.context.tabID ?? "none")-item"])
        })
        let viewModel: LibraryViewModel = Harness.makeLibraryViewModel(
            database: database,
            resolver: Harness.resolver([source.id: runtime])
        )
        _ = await viewModel.loadIfNeeded()
        let tabs: [LibraryListTabState] = viewModel.listTabStates
        try #require(tabs.count >= 2)
        #expect(tabs.first?.isSelected == true)
        let firstTabID: String? = runtime.listInputs.first?.context.tabID

        await viewModel.selectListTab(id: tabs[1].id)

        #expect(viewModel.selectedListTabID == tabs[1].id)
        #expect(runtime.listInputs.count == 2)
        let secondTabID: String? = runtime.listInputs.last?.context.tabID
        #expect(secondTabID != nil)
        #expect(secondTabID != firstTabID)
        #expect(viewModel.items.map(\.id) == ["\(secondTabID ?? "none")-item"])
        #expect(viewModel.selectedListTabErrorMessage == nil)
    }

    @Test func selectionStoreSwitchClearsItemsAndRefreshesTheNewSource() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let comic: Source = try Harness.makeComicSource(id: "built-in.comic")
        let custom: Source = try Harness.makeComicSource(id: "comic.custom")
        let sourceRepository: GRDBSourceRepository = GRDBSourceRepository(database: database)
        try sourceRepository.saveSource(comic)
        try sourceRepository.saveSource(custom)
        let comicRuntime: ScriptedSourceRuntime = ScriptedSourceRuntime(source: comic, list: { _ in
            ScriptedSourceRuntime.listOutput(ids: ["comic-1"])
        })
        let customRuntime: ScriptedSourceRuntime = ScriptedSourceRuntime(source: custom, list: { _ in
            ScriptedSourceRuntime.listOutput(ids: ["custom-1"])
        })
        let store: SourceSelectionStore = SourceSelectionStore()
        let viewModel: LibraryViewModel = Harness.makeLibraryViewModel(
            database: database,
            resolver: Harness.resolver([comic.id: comicRuntime, custom.id: customRuntime]),
            selectionStore: store
        )
        _ = await viewModel.loadIfNeeded()
        let initialSourceID: String = try #require(viewModel.selectedSourceID)
        let otherSourceID: String = initialSourceID == comic.id ? custom.id : comic.id
        #expect(viewModel.items.count == 1)

        store.selectedSourceID = otherSourceID

        let switched: Bool = await Harness.waitUntil {
            viewModel.selectedSourceID == otherSourceID
        }
        #expect(switched)
        #expect(viewModel.items.isEmpty)
        #expect(viewModel.selectedListTabErrorMessage == nil)

        let outcome: LibraryInitialLoadOutcome = await viewModel.refreshSelectedListTab()

        #expect(outcome == .loaded)
        let expectedItemID: String = otherSourceID == comic.id ? "comic-1" : "custom-1"
        #expect(viewModel.items.map(\.id) == [expectedItemID])
    }

    // MARK: - 列表分页（2026-09-12 真机「漫画不翻页」倒查：ViewModel 与内容视图把翻页写死成只有影视）

    @Test func comicListAdvancesToTheNextPageWhenRuntimeReportsOne() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let source: Source = try Harness.makeComicSource()
        try GRDBSourceRepository(database: database).saveSource(source)
        let runtime: ScriptedSourceRuntime = ScriptedSourceRuntime(source: source, list: { input in
            switch input.page {
            case 1:
                return ScriptedSourceRuntime.listOutput(ids: ["a", "b"], nextPage: 2)
            case 2:
                return ScriptedSourceRuntime.listOutput(ids: ["c"], nextPage: nil)
            default:
                throw TestPortError(reason: "unexpected page \(input.page)")
            }
        })
        let viewModel: LibraryViewModel = Harness.makeLibraryViewModel(
            database: database,
            resolver: Harness.resolver([source.id: runtime])
        )

        let outcome: LibraryInitialLoadOutcome = await viewModel.loadIfNeeded()

        #expect(outcome == .loaded)
        #expect(viewModel.items.map(\.id) == ["a", "b"])
        #expect(viewModel.canLoadNextPage)
        #expect(viewModel.nextListPage == 2)
        #expect(viewModel.shouldShowPaginationStatus)

        await viewModel.loadNextPageIfNeeded()

        #expect(viewModel.items.map(\.id) == ["a", "b", "c"])
        #expect(viewModel.currentListPage == 2)
        #expect(viewModel.canLoadNextPage == false)
        #expect(viewModel.nextListPage == nil)
        #expect(viewModel.isLoadingNextPage == false)
        #expect(runtime.listInputs.map(\.page) == [1, 2])
    }

    @Test func comicListWithoutPaginationNeverAsksForANextPage() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let source: Source = try Harness.makeComicSource()
        try GRDBSourceRepository(database: database).saveSource(source)
        let runtime: ScriptedSourceRuntime = ScriptedSourceRuntime(source: source, list: { _ in
            ScriptedSourceRuntime.listOutput(ids: ["a"])
        })
        let viewModel: LibraryViewModel = Harness.makeLibraryViewModel(
            database: database,
            resolver: Harness.resolver([source.id: runtime])
        )

        _ = await viewModel.loadIfNeeded()
        #expect(viewModel.canLoadNextPage == false)
        #expect(viewModel.nextListPage == nil)

        await viewModel.loadNextPageIfNeeded()

        #expect(viewModel.items.map(\.id) == ["a"])
        #expect(runtime.listInputs.map(\.page) == [1])
    }

    // 中文注释：2026-09-14 biquhua 模拟器复验——规则带分页模板、Runtime 报 nextPage=2，
    // 但 `selectedSourceSupportsListPagination` 只认 video / comic，book 的触底哨兵永远不挂。
    @Test func bookListAdvancesToTheNextPageWhenRuntimeReportsOne() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let source: Source = try Harness.makeBookSource()
        try GRDBSourceRepository(database: database).saveSource(source)
        let runtime: ScriptedSourceRuntime = ScriptedSourceRuntime(source: source, list: { input in
            switch input.page {
            case 1:
                return ScriptedSourceRuntime.listOutput(ids: ["a", "b"], nextPage: 2)
            case 2:
                return ScriptedSourceRuntime.listOutput(ids: ["c"], nextPage: nil)
            default:
                throw TestPortError(reason: "unexpected page \(input.page)")
            }
        })
        let viewModel: LibraryViewModel = Harness.makeLibraryViewModel(
            database: database,
            resolver: Harness.resolver([source.id: runtime])
        )

        let outcome: LibraryInitialLoadOutcome = await viewModel.loadIfNeeded()
        #expect(viewModel.selectedSource?.id == source.id)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.selectedListTabErrorMessage == nil)
        #expect(outcome == .loaded)
        #expect(viewModel.canLoadNextPage)
        #expect(viewModel.nextListPage == 2)
        #expect(viewModel.shouldShowPaginationStatus)

        await viewModel.loadNextPageIfNeeded()

        #expect(viewModel.items.map(\.id) == ["a", "b", "c"])
        #expect(viewModel.currentListPage == 2)
        #expect(viewModel.nextListPage == nil)
        #expect(runtime.listInputs.map(\.page) == [1, 2])
    }

}
