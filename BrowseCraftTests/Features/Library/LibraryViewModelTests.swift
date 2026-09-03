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
        let rss: Source = Harness.makeRSSSource(id: "rss.custom")
        let sourceRepository: GRDBSourceRepository = GRDBSourceRepository(database: database)
        try sourceRepository.saveSource(comic)
        try sourceRepository.saveSource(rss)
        try GRDBUserLibraryStateRepository(database: database).save(
            UserLibraryState(
                userID: AppUser.localDefaultID,
                selectedSourceID: rss.id,
                listContext: nil,
                lastRefreshAt: nil,
                updatedAt: Harness.fixedNow
            )
        )
        let comicRuntime: ScriptedSourceRuntime = ScriptedSourceRuntime(source: comic)
        let rssRuntime: ScriptedSourceRuntime = ScriptedSourceRuntime(source: rss, list: { _ in
            ScriptedSourceRuntime.listOutput(ids: ["rss-1"])
        })
        let viewModel: LibraryViewModel = Harness.makeLibraryViewModel(
            database: database,
            resolver: Harness.resolver([comic.id: comicRuntime, rss.id: rssRuntime])
        )

        let outcome: LibraryInitialLoadOutcome = await viewModel.loadIfNeeded()

        #expect(outcome == .loaded)
        #expect(viewModel.selectedSourceID == rss.id)
        #expect(viewModel.items.map(\.id) == ["rss-1"])
        #expect(viewModel.items.first?.type == .article)
        #expect(rssRuntime.listInputs.count == 1)
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
        let rss: Source = Harness.makeRSSSource(id: "rss.custom")
        let sourceRepository: GRDBSourceRepository = GRDBSourceRepository(database: database)
        try sourceRepository.saveSource(comic)
        try sourceRepository.saveSource(rss)
        let comicRuntime: ScriptedSourceRuntime = ScriptedSourceRuntime(source: comic, list: { _ in
            ScriptedSourceRuntime.listOutput(ids: ["comic-1"])
        })
        let rssRuntime: ScriptedSourceRuntime = ScriptedSourceRuntime(source: rss, list: { _ in
            ScriptedSourceRuntime.listOutput(ids: ["rss-1"])
        })
        let store: SourceSelectionStore = SourceSelectionStore()
        let viewModel: LibraryViewModel = Harness.makeLibraryViewModel(
            database: database,
            resolver: Harness.resolver([comic.id: comicRuntime, rss.id: rssRuntime]),
            selectionStore: store
        )
        _ = await viewModel.loadIfNeeded()
        let initialSourceID: String = try #require(viewModel.selectedSourceID)
        let otherSourceID: String = initialSourceID == comic.id ? rss.id : comic.id
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
        let expectedItemID: String = otherSourceID == comic.id ? "comic-1" : "rss-1"
        #expect(viewModel.items.map(\.id) == [expectedItemID])
    }
}
