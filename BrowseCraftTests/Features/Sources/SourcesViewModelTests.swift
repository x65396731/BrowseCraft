import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft
import BrowseCraftDomain

// 中文注释：SourcesViewModel 状态机测试——真实 GRDB 持久化 + 脚本 runtime / feed loader，
// 覆盖启动读取、添加 RSS 源、删除、选源刷新与重试、槽位锁定与替换。
@MainActor
struct SourcesViewModelTests {
    private typealias Harness = ViewModelTestHarness

    @Test func startupWithoutSourcesReturnsFalse() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let viewModel: SourcesViewModel = Harness.makeSourcesViewModel(
            database: database,
            resolver: Harness.resolver()
        )

        let hasSources: Bool = try await viewModel.loadForStartup()

        #expect(hasSources == false)
        #expect(viewModel.sources.isEmpty)
        #expect(viewModel.selectedSourceID == nil)
        #expect(viewModel.sourceSlotLimit == SourceSlotPolicy.includedSiteSlotCount)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func startupSelectsTheFirstActiveSource() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let source: Source = Harness.makeRSSSource()
        try GRDBSourceRepository(database: database).saveSource(source)
        let store: SourceSelectionStore = SourceSelectionStore()
        let viewModel: SourcesViewModel = Harness.makeSourcesViewModel(
            database: database,
            resolver: Harness.resolver(),
            selectionStore: store
        )

        let hasSources: Bool = try await viewModel.loadForStartup()

        #expect(hasSources)
        #expect(viewModel.sources.map(\.id) == [source.id])
        // 中文注释：启动读取不自行选源；当前 source 由 Library 恢复后经 SourceSelectionStore 回传。
        #expect(viewModel.selectedSourceID == nil)

        store.selectedSourceID = source.id

        let mirrored: Bool = await Harness.waitUntil { viewModel.selectedSourceID == source.id }
        #expect(mirrored)
        #expect(viewModel.occupiedSourceSlotCount == 1)
        #expect(viewModel.lockedSourceCount == 0)
    }

    @Test func addRSSSourcePersistsSelectsAndPublishesSnapshot() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let feedLoader: ScriptedRSSFeedLoader = ScriptedRSSFeedLoader(
            result: .success(RSSFeed(title: "Example Feed", items: []))
        )
        let runtime: ScriptedSourceRuntime = ScriptedSourceRuntime(
            source: Harness.makeRSSSource(id: "placeholder"),
            list: { _ in
                ScriptedSourceRuntime.listOutput(ids: ["1", "2"])
            }
        )
        let store: SourceSelectionStore = SourceSelectionStore()
        let viewModel: SourcesViewModel = Harness.makeSourcesViewModel(
            database: database,
            resolver: Harness.resolver(fallback: runtime),
            selectionStore: store,
            rssFeedLoader: feedLoader
        )

        let added: Source? = await viewModel.addRSSSource(feedURLString: "https://example.test/feed.xml")

        let addedSource: Source = try #require(added)
        #expect(viewModel.errorMessage == nil)
        #expect(feedLoader.requestedFeedURLs == [URL(string: "https://example.test/feed.xml")!])
        #expect(viewModel.sources.map(\.id) == [addedSource.id])
        #expect(viewModel.selectedSourceID == addedSource.id)
        #expect(viewModel.latestSourceAddID == addedSource.id)
        #expect(store.selectedSourceID == addedSource.id)
        #expect(store.preparedLibrarySnapshot?.sourceID == addedSource.id)
        #expect(store.preparedLibrarySnapshot?.items.map(\.id) == ["1", "2"])
        #expect(runtime.listInputs.count == 1)

        let persisted: [Source] = try GRDBSourceRepository(database: database).fetchSources()
        #expect(persisted.map(\.id) == [addedSource.id])
        #expect(persisted.first?.configuration.kind == .rss)
        guard case .rss(let configuration)? = persisted.first?.configuration else {
            Issue.record("Expected an RSS configuration for the added source.")
            return
        }
        #expect(configuration.definition.feedURL.absoluteString == "https://example.test/feed.xml")
    }

    @Test func addRSSSourceFailureKeepsListUntouchedAndReportsError() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let feedLoader: ScriptedRSSFeedLoader = ScriptedRSSFeedLoader(
            result: .failure(TestPortError(reason: "feed unreachable"))
        )
        let viewModel: SourcesViewModel = Harness.makeSourcesViewModel(
            database: database,
            resolver: Harness.resolver(),
            rssFeedLoader: feedLoader
        )

        let added: Source? = await viewModel.addRSSSource(feedURLString: "https://example.test/feed.xml")

        #expect(added == nil)
        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.sources.isEmpty)
        #expect(viewModel.latestSourceAddID == nil)
        #expect(try GRDBSourceRepository(database: database).fetchSources().isEmpty)
    }

    @Test func deletingTheSelectedSourceMovesSelectionToTheRemainingOne() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let comic: Source = try Harness.makeComicSource(id: "built-in.comic")
        let rss: Source = Harness.makeRSSSource(id: "rss.custom")
        let sourceRepository: GRDBSourceRepository = GRDBSourceRepository(database: database)
        try sourceRepository.saveSource(comic)
        try sourceRepository.saveSource(rss)
        let viewModel: SourcesViewModel = Harness.makeSourcesViewModel(
            database: database,
            resolver: Harness.resolver()
        )
        _ = try await viewModel.loadForStartup()
        viewModel.selectSource(id: comic.id)
        let selectedID: String = try #require(viewModel.selectedSourceID)
        let selectedIndex: Int = try #require(viewModel.sources.firstIndex { source in source.id == selectedID })
        let remainingID: String = selectedID == comic.id ? rss.id : comic.id

        await viewModel.deleteSources(at: IndexSet(integer: selectedIndex))

        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.sources.map(\.id) == [remainingID])
        #expect(viewModel.selectedSourceID == remainingID)
        #expect(try sourceRepository.fetchSources().map(\.id) == [remainingID])
    }

    @Test func selectSourceAfterRefreshPublishesSnapshotAndRetriesAfterFailure() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let comic: Source = try Harness.makeComicSource(id: "built-in.comic")
        let rss: Source = Harness.makeRSSSource(id: "rss.custom")
        let sourceRepository: GRDBSourceRepository = GRDBSourceRepository(database: database)
        try sourceRepository.saveSource(comic)
        try sourceRepository.saveSource(rss)
        let comicRuntime: ScriptedSourceRuntime = ScriptedSourceRuntime(source: comic, list: { _ in
            throw TestPortError(reason: "first attempt fails")
        })
        let rssRuntime: ScriptedSourceRuntime = ScriptedSourceRuntime(source: rss, list: { _ in
            throw TestPortError(reason: "first attempt fails")
        })
        let store: SourceSelectionStore = SourceSelectionStore()
        let viewModel: SourcesViewModel = Harness.makeSourcesViewModel(
            database: database,
            resolver: Harness.resolver([comic.id: comicRuntime, rss.id: rssRuntime]),
            selectionStore: store
        )
        _ = try await viewModel.loadForStartup()
        viewModel.selectSource(id: comic.id)
        let initialID: String = try #require(viewModel.selectedSourceID)
        let target: Source = try #require(viewModel.sources.first { source in source.id != initialID })
        let targetRuntime: ScriptedSourceRuntime = target.id == comic.id ? comicRuntime : rssRuntime

        await viewModel.selectSourceAfterRefresh(target)

        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.selectedSourceID == initialID)
        #expect(viewModel.isRefreshing == false)
        #expect(store.preparedLibrarySnapshot == nil)
        #expect(targetRuntime.listInputs.count == 1)

        targetRuntime.setListHandler { _ in
            ScriptedSourceRuntime.listOutput(ids: ["retry-1"])
        }
        await viewModel.retryFailedRefresh()

        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.selectedSourceID == target.id)
        #expect(store.selectedSourceID == target.id)
        #expect(store.preparedLibrarySnapshot?.sourceID == target.id)
        #expect(store.preparedLibrarySnapshot?.items.map(\.id) == ["retry-1"])
        #expect(targetRuntime.listInputs.count == 2)
    }

    @Test func lockedSourceRequiresSlotActivationAndReplacementSwapsSlots() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let first: Source = try Harness.makeComicSource(id: "custom.first", name: "First")
        var second: Source = try Harness.makeComicSource(id: "custom.second", name: "Second")
        let sourceRepository: GRDBSourceRepository = GRDBSourceRepository(database: database)
        try sourceRepository.saveSource(first)
        // 中文注释：仓储拒绝第二个激活的自定义源（siteSlotLimitReached）；被锁的源以 enabled == false 存在。
        #expect(throws: SourceRepositoryError.siteSlotLimitReached(limit: 1)) {
            try sourceRepository.saveSource(second)
        }
        second.enabled = false
        try sourceRepository.saveSource(second)
        let viewModel: SourcesViewModel = Harness.makeSourcesViewModel(
            database: database,
            resolver: Harness.resolver()
        )
        _ = try await viewModel.loadForStartup()

        #expect(viewModel.sourceSlotLimit == 1)
        #expect(viewModel.occupiedSourceSlotCount == 1)
        #expect(viewModel.lockedSourceCount == 1)
        let active: Source = try #require(viewModel.sources.first { source in source.accessState == .active })
        let locked: Source = try #require(viewModel.sources.first { source in source.accessState == .lockedBySlotLimit })
        #expect(active.id == first.id)
        #expect(locked.id == second.id)
        viewModel.selectSource(id: active.id)
        #expect(viewModel.selectedSourceID == active.id)

        viewModel.selectSource(id: locked.id)

        #expect(viewModel.requestedSlotActivationSource?.id == locked.id)
        #expect(viewModel.selectedSourceID == active.id)

        let activated: Bool = await viewModel.activateRequestedSource(replacingSourceID: active.id)

        #expect(activated)
        #expect(viewModel.requestedSlotActivationSource == nil)
        #expect(viewModel.source(id: locked.id)?.accessState == .active)
        #expect(viewModel.source(id: active.id)?.accessState == .lockedBySlotLimit)
        #expect(viewModel.occupiedSourceSlotCount == 1)
        let persisted: [Source] = try sourceRepository.fetchSources()
        #expect(persisted.first { source in source.id == locked.id }?.enabled == true)
        #expect(persisted.first { source in source.id == active.id }?.enabled == false)
    }
}
