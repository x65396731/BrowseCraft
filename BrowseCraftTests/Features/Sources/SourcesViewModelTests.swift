import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft
import BrowseCraftDomain

// 中文注释：SourcesViewModel 状态机测试——真实 GRDB 持久化 + 脚本 runtime / feed loader，
// 覆盖启动读取、删除、选源刷新与重试、槽位锁定与替换。
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
        let source: Source = try Harness.makeComicSource()
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

    // 中文注释：2026-09-14 biquhua 复验倒查——服务器替换了规则，已添加的来源拿不到新版本。
    // 目录条目与本地规则同形 → 无更新；服务器版多了 content.next → 有更新；更新后本地规则换新、createdAt 不动。
    @Test func catalogSourceWithNewerRuleOffersAnUpdateAndAppliesItInPlace() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let existing: Source = try Harness.makeBookSource()
        try GRDBSourceRepository(database: database).saveSource(existing)
        let viewModel: SourcesViewModel = Harness.makeSourcesViewModel(
            database: database,
            resolver: Harness.resolver()
        )
        _ = try await viewModel.loadForStartup()

        let same: CatalogSource = try Harness.makeBookCatalogSource(fixture: "biquhua-catalog")
        let newer: CatalogSource = try Harness.makeBookCatalogSource(fixture: "biquhua-catalog-next")
        #expect(viewModel.isCatalogSourceAdded(same))
        #expect(viewModel.catalogSourceHasRuleUpdate(same) == false)
        #expect(viewModel.catalogSourceHasRuleUpdate(newer))

        let didUpdate: Bool = await viewModel.addCatalogSource(newer, shouldPresentError: false)

        #expect(didUpdate)
        #expect(viewModel.catalogSourceHasRuleUpdate(newer) == false)
        #expect(viewModel.catalogSourceHasRuleUpdate(same))
        let stored: Source = try #require(try GRDBSourceRepository(database: database).fetchSources().first { $0.id == existing.id })
        #expect(stored.createdAt == existing.createdAt)
        guard case .book(let configuration) = stored.configuration else {
            Issue.record("expected .book configuration")
            return
        }
        #expect(configuration.rule.ruleSets.readerRules.first?.content?.next != nil)
    }

    // 中文注释：2026-09-30 用户裁定——推荐由服务器给，已添加的来源跟随目录自动覆盖，不再有手动「更新」。
    // 目录里同 id 的新版规则直接覆盖本地（createdAt 不动）；目录里未添加的条目不会被顺手加进来。
    @Test func addedSourcesFollowTheCatalogWithoutATap() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let existing: Source = try Harness.makeBookSource()
        try GRDBSourceRepository(database: database).saveSource(existing)
        let viewModel: SourcesViewModel = Harness.makeSourcesViewModel(
            database: database,
            resolver: Harness.resolver()
        )
        _ = try await viewModel.loadForStartup()

        let newer: CatalogSource = try Harness.makeBookCatalogSource(fixture: "biquhua-catalog-next")
        let notAdded: CatalogSource = CatalogSource(
            id: "\(newer.id)-not-added",
            name: newer.name,
            baseURL: newer.baseURL,
            kind: newer.kind,
            ruleJSON: newer.ruleJSON
        )
        #expect(viewModel.isCatalogSourceAdded(notAdded) == false)

        await viewModel.applyCatalogRuleUpdates([newer, notAdded])

        #expect(viewModel.catalogSourceHasRuleUpdate(newer) == false)
        #expect(viewModel.isCatalogSourceAdded(notAdded) == false)
        let stored: Source = try #require(try GRDBSourceRepository(database: database).fetchSources().first { $0.id == existing.id })
        #expect(stored.createdAt == existing.createdAt)
        guard case .book(let configuration) = stored.configuration else {
            Issue.record("expected .book configuration")
            return
        }
        #expect(configuration.rule.ruleSets.readerRules.first?.content?.next != nil)
    }

    @Test func deletingTheSelectedSourceMovesSelectionToTheRemainingOne() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let comic: Source = try Harness.makeComicSource(id: "built-in.comic")
        let custom: Source = try Harness.makeComicSource(id: "comic.custom")
        let sourceRepository: GRDBSourceRepository = GRDBSourceRepository(database: database)
        try sourceRepository.saveSource(comic)
        try sourceRepository.saveSource(custom)
        let viewModel: SourcesViewModel = Harness.makeSourcesViewModel(
            database: database,
            resolver: Harness.resolver()
        )
        _ = try await viewModel.loadForStartup()
        viewModel.selectSource(id: comic.id)
        let selectedID: String = try #require(viewModel.selectedSourceID)
        let selectedIndex: Int = try #require(viewModel.sources.firstIndex { source in source.id == selectedID })
        let remainingID: String = selectedID == comic.id ? custom.id : comic.id

        await viewModel.deleteSources(at: IndexSet(integer: selectedIndex))

        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.sources.map(\.id) == [remainingID])
        #expect(viewModel.selectedSourceID == remainingID)
        #expect(try sourceRepository.fetchSources().map(\.id) == [remainingID])
    }

    @Test func selectSourceAfterRefreshPublishesSnapshotAndRetriesAfterFailure() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let comic: Source = try Harness.makeComicSource(id: "built-in.comic")
        let custom: Source = try Harness.makeComicSource(id: "comic.custom")
        let sourceRepository: GRDBSourceRepository = GRDBSourceRepository(database: database)
        try sourceRepository.saveSource(comic)
        try sourceRepository.saveSource(custom)
        let comicRuntime: ScriptedSourceRuntime = ScriptedSourceRuntime(source: comic, list: { _ in
            throw TestPortError(reason: "first attempt fails")
        })
        let customRuntime: ScriptedSourceRuntime = ScriptedSourceRuntime(source: custom, list: { _ in
            throw TestPortError(reason: "first attempt fails")
        })
        let store: SourceSelectionStore = SourceSelectionStore()
        let viewModel: SourcesViewModel = Harness.makeSourcesViewModel(
            database: database,
            resolver: Harness.resolver([comic.id: comicRuntime, custom.id: customRuntime]),
            selectionStore: store
        )
        _ = try await viewModel.loadForStartup()
        viewModel.selectSource(id: comic.id)
        let initialID: String = try #require(viewModel.selectedSourceID)
        let target: Source = try #require(viewModel.sources.first { source in source.id != initialID })
        let targetRuntime: ScriptedSourceRuntime = target.id == comic.id ? comicRuntime : customRuntime

        // 中文注释：来源页据返回值决定是否跳到库——加载第一页失败时不跳（`Sources-Page-Redesign-Design.md` 2.3）。
        let firstAttemptSelected: Bool = await viewModel.selectSourceAfterRefresh(target)

        #expect(firstAttemptSelected == false)
        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.selectedSourceID == initialID)
        #expect(viewModel.isRefreshing == false)
        #expect(store.preparedLibrarySnapshot == nil)
        #expect(targetRuntime.listInputs.count == 1)

        targetRuntime.setListHandler { _ in
            ScriptedSourceRuntime.listOutput(ids: ["retry-1"])
        }
        let retrySelected: Bool = await viewModel.retryFailedRefresh()

        #expect(retrySelected)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.selectedSourceID == target.id)
        #expect(store.selectedSourceID == target.id)
        #expect(store.preparedLibrarySnapshot?.sourceID == target.id)
        #expect(store.preparedLibrarySnapshot?.items.map(\.id) == ["retry-1"])
        #expect(targetRuntime.listInputs.count == 2)

        // 中文注释：点当前来源直接打开库：返回 true，不再加载第一页。
        let currentSelected: Bool = await viewModel.selectSourceAfterRefresh(target)
        #expect(currentSelected)
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

        // 中文注释：正在使用的来源不会被「请求启用」打开启用窗口。
        viewModel.requestSlotActivation(for: active)
        #expect(viewModel.requestedSlotActivationSource == nil)

        // 中文注释：点已暂停的来源不切换、不跳库，而是打开启用窗口。
        let lockedSelected: Bool = await viewModel.selectSourceAfterRefresh(locked)

        #expect(lockedSelected == false)
        #expect(viewModel.requestedSlotActivationSource?.id == locked.id)
        #expect(viewModel.selectedSourceID == active.id)
        viewModel.dismissRequestedSlotActivation()
        viewModel.requestSlotActivation(for: locked)
        #expect(viewModel.requestedSlotActivationSource?.id == locked.id)

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

    // 中文注释：「已暂停」的来历之一——启用的来源比位置多（iCloud 合并进来的来源、或本机读到的位置额度变少）。
    // 每次读列表时按「启用在前、最近更新在前」只留前 N 个占位置，其余暂停；当前来源被暂停时选中挪到仍在用的来源。
    @Test func sourcesBeyondTheSlotLimitArePausedKeepingTheMostRecentlyUpdated() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let sourceRepository: GRDBSourceRepository = GRDBSourceRepository(database: database)
        let oldest: Source = try Harness.makeComicSource(id: "custom.oldest", name: "Oldest")
        let middle: Source = try Harness.makeComicSource(id: "custom.middle", name: "Middle")
        let newest: Source = try Harness.makeComicSource(id: "custom.newest", name: "Newest")
        try sourceRepository.saveSource(oldest)
        try Self.setSiteSlotLimit(3, in: database)
        try sourceRepository.saveSource(middle)
        try sourceRepository.saveSource(newest)
        try Self.setUpdatedAt(
            [oldest.id: Harness.fixedNow.addingTimeInterval(-300),
             middle.id: Harness.fixedNow.addingTimeInterval(-200),
             newest.id: Harness.fixedNow.addingTimeInterval(-100)],
            in: database
        )
        let viewModel: SourcesViewModel = Harness.makeSourcesViewModel(
            database: database,
            resolver: Harness.resolver()
        )
        _ = try await viewModel.loadForStartup()
        #expect(viewModel.occupiedSourceSlotCount == 3)
        #expect(viewModel.lockedSourceCount == 0)
        viewModel.selectSource(id: middle.id)

        try Self.setSiteSlotLimit(1, in: database)
        await viewModel.load()

        #expect(viewModel.sourceSlotLimit == 1)
        #expect(viewModel.occupiedSourceSlotCount == 1)
        #expect(viewModel.lockedSourceCount == 2)
        #expect(viewModel.source(id: newest.id)?.accessState == .active)
        #expect(viewModel.source(id: middle.id)?.accessState == .lockedBySlotLimit)
        #expect(viewModel.source(id: oldest.id)?.accessState == .lockedBySlotLimit)
        #expect(viewModel.selectedSourceID == newest.id)
        #expect(viewModel.canActivateRequestedSourceWithoutReplacement == false)
        let persisted: [Source] = try sourceRepository.fetchSources()
        #expect(persisted.filter(\.enabled).map(\.id) == [newest.id])

        // 中文注释：位置额度回来后（买了位置），暂停的来源在下一次读列表时自动恢复。
        try Self.setSiteSlotLimit(3, in: database)
        await viewModel.load()

        #expect(viewModel.occupiedSourceSlotCount == 3)
        #expect(viewModel.lockedSourceCount == 0)
    }

    // 中文注释：iCloud 同步直接写进来的启用记录不经过 `saveSource` 的位置检查；读列表时同样归置成暂停。
    @Test func syncedSourceArrivingOverTheLimitIsPaused() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let sourceRepository: GRDBSourceRepository = GRDBSourceRepository(database: database)
        let local: Source = try Harness.makeComicSource(id: "custom.local", name: "Local")
        var synced: Source = try Harness.makeComicSource(id: "custom.synced", name: "Synced")
        try sourceRepository.saveSource(local)
        synced.enabled = false
        try sourceRepository.saveSource(synced)
        try Self.markEnabled(synced.id, in: database)
        try Self.setUpdatedAt(
            [synced.id: Harness.fixedNow.addingTimeInterval(-500),
             local.id: Harness.fixedNow.addingTimeInterval(-100)],
            in: database
        )
        let viewModel: SourcesViewModel = Harness.makeSourcesViewModel(
            database: database,
            resolver: Harness.resolver()
        )

        _ = try await viewModel.loadForStartup()

        #expect(viewModel.occupiedSourceSlotCount == 1)
        #expect(viewModel.source(id: local.id)?.accessState == .active)
        #expect(viewModel.source(id: synced.id)?.accessState == .lockedBySlotLimit)
    }

    // 中文注释：长按 / 左滑按来源删除；删掉正在用的来源后位置空出，暂停的来源在同一次归置里补上。
    @Test func deletingTheActiveSourceByIDLetsAPausedSourceTakeTheSlot() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let sourceRepository: GRDBSourceRepository = GRDBSourceRepository(database: database)
        let active: Source = try Harness.makeComicSource(id: "custom.active", name: "Active")
        var paused: Source = try Harness.makeComicSource(id: "custom.paused", name: "Paused")
        try sourceRepository.saveSource(active)
        paused.enabled = false
        try sourceRepository.saveSource(paused)
        let viewModel: SourcesViewModel = Harness.makeSourcesViewModel(
            database: database,
            resolver: Harness.resolver()
        )
        _ = try await viewModel.loadForStartup()
        viewModel.selectSource(id: active.id)
        #expect(viewModel.source(id: paused.id)?.accessState == .lockedBySlotLimit)

        await viewModel.deleteSource(id: active.id)

        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.sources.map(\.id) == [paused.id])
        #expect(viewModel.source(id: paused.id)?.accessState == .active)
        #expect(viewModel.selectedSourceID == paused.id)
        #expect(try sourceRepository.fetchSources().map(\.id) == [paused.id])
    }

    private static func setSiteSlotLimit(_ limit: Int, in database: AppDatabase) throws {
        try database.queue.write { database in
            try database.execute(
                sql: "UPDATE \(AppUserRecord.databaseTableName) SET siteSlotLimit = ?",
                arguments: [limit]
            )
        }
    }

    /// 模拟同步直接写入一条启用记录，绕过 `saveSource` 的位置检查。
    private static func markEnabled(_ sourceID: String, in database: AppDatabase) throws {
        try database.queue.write { database in
            try database.execute(
                sql: "UPDATE \(SourceRecord.databaseTableName) SET enabled = 1 WHERE id = ?",
                arguments: [sourceID]
            )
        }
    }

    private static func setUpdatedAt(_ dates: [String: Date], in database: AppDatabase) throws {
        try database.queue.write { database in
            for (sourceID, date) in dates {
                try database.execute(
                    sql: "UPDATE \(SourceRecord.databaseTableName) SET updatedAt = ? WHERE id = ?",
                    arguments: [date, sourceID]
                )
            }
        }
    }
}
