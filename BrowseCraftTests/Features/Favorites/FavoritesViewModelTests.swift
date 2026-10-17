import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft
import BrowseCraftDomain

// 中文注释：收藏页重设计（`docs/design/Favorites-Page-Redesign-Design.md`）的 ViewModel 测试——
// 真实 GRDB 收藏与来源仓储，覆盖类型计数、按天分组、来源状态、取消收藏与选择模式下的批量取消收藏。
@MainActor
struct FavoritesViewModelTests {
    private typealias Harness = ViewModelTestHarness

    /// 本地日历上「今天中午」，分组判定不受测试运行时刻与时区影响。
    private static let noon: Date = Calendar.current.date(
        bySettingHour: 12,
        minute: 0,
        second: 0,
        of: Date()
    )!

    @Test func countsEveryKindAndGroupsByFavoriteDayNewestFirst() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let favorites: GRDBFavoriteRepository = GRDBFavoriteRepository(database: database)
        try favorites.restoreFavorite(item: Self.item(id: "video-older", kind: .videoNative, hoursAgo: 2))
        try favorites.restoreFavorite(item: Self.item(id: "video-newer", kind: .videoWeb, hoursAgo: 1))
        try favorites.restoreFavorite(item: Self.item(id: "comic", kind: .comic, hoursAgo: 24))
        let viewModel: FavoritesViewModel = Self.makeViewModel(database: database)

        await viewModel.load()

        #expect(viewModel.count(for: .all) == 3)
        #expect(viewModel.count(for: .video) == 2)
        #expect(viewModel.count(for: .comic) == 1)
        // 中文注释：三类标签一直显示，没有收藏的类型计数为 0。
        #expect(viewModel.count(for: .book) == 0)
        let groups: [FavoritesViewModel.DayGroup] = viewModel.dayGroups
        #expect(groups.map(\.day) == [.today, .yesterday])
        #expect(groups.first?.items.map(\.id) == ["video-newer", "video-older"])

        viewModel.kindFilter = .comic
        #expect(viewModel.dayGroups.map(\.day) == [.yesterday])

        viewModel.kindFilter = .book
        #expect(viewModel.dayGroups.isEmpty)
    }

    @Test func sourceStateFollowsTheSourceBehindEachFavorite() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let sourceRepository: GRDBSourceRepository = GRDBSourceRepository(database: database)
        let active: Source = try Harness.makeComicSource(id: "custom.active", name: "Active")
        var paused: Source = try Harness.makeComicSource(id: "custom.paused", name: "Paused")
        try sourceRepository.saveSource(active)
        paused.enabled = false
        try sourceRepository.saveSource(paused)
        let deleted: Source = try Harness.makeComicSource(id: "custom.deleted", name: "Deleted")

        let favorites: GRDBFavoriteRepository = GRDBFavoriteRepository(database: database)
        let onActive: FavoriteContentItem = Self.item(id: "on-active", sourceID: active.id, hoursAgo: 1)
        let onPaused: FavoriteContentItem = Self.item(id: "on-paused", sourceID: paused.id, hoursAgo: 2)
        let onDeleted: FavoriteContentItem = Self.item(
            id: "on-deleted",
            sourceID: deleted.id,
            hoursAgo: 3,
            snapshot: FavoriteSourceSnapshot(source: deleted)
        )
        let onUnknown: FavoriteContentItem = Self.item(id: "on-unknown", sourceID: "custom.gone", hoursAgo: 4)
        for item in [onActive, onPaused, onDeleted, onUnknown] {
            try favorites.restoreFavorite(item: item)
        }
        let viewModel: FavoritesViewModel = Self.makeViewModel(database: database)

        await viewModel.load()

        #expect(viewModel.sourceState(for: onActive) == .available)
        #expect(viewModel.sourceState(for: onPaused) == .paused)
        #expect(viewModel.sourceState(for: onDeleted) == .deleted)
        #expect(viewModel.sourceName(for: onDeleted) == "Deleted")
        #expect(viewModel.sourceState(for: onUnknown) == .unknown)
        #expect(viewModel.source(for: onUnknown) == nil)
        #expect(viewModel.sourceName(for: onUnknown) == NSLocalizedString("favorites_unknown_source", comment: ""))
    }

    @Test func unfavoritingRemovesTheItemWithoutUndo() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let favorites: GRDBFavoriteRepository = GRDBFavoriteRepository(database: database)
        try favorites.restoreFavorite(item: Self.item(id: "comic", kind: .comic, hoursAgo: 24))
        let viewModel: FavoritesViewModel = Self.makeViewModel(database: database)
        await viewModel.load()
        let stored: FavoriteContentItem = try #require(viewModel.favoriteItems.first)

        await viewModel.unfavorite(stored)

        #expect(viewModel.favoriteItems.isEmpty)
        #expect(viewModel.changeRevision == 1)
        #expect(try favorites.fetchFavoriteItemIDs().isEmpty)
    }

    // 中文注释：选择模式（设计文档 2.5）：「全选」只选当前筛选下的条目；批量取消收藏后退出选择模式。
    @Test func selectionUnfavoritesOnlyTheChosenItemsInTheCurrentFilter() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let favorites: GRDBFavoriteRepository = GRDBFavoriteRepository(database: database)
        try favorites.restoreFavorite(item: Self.item(id: "video-a", kind: .videoNative, hoursAgo: 1))
        try favorites.restoreFavorite(item: Self.item(id: "video-b", kind: .videoWeb, hoursAgo: 2))
        try favorites.restoreFavorite(item: Self.item(id: "comic", kind: .comic, hoursAgo: 3))
        let viewModel: FavoritesViewModel = Self.makeViewModel(database: database)
        await viewModel.load()

        viewModel.kindFilter = .video
        let first: FavoriteContentItem = try #require(viewModel.visibleItems.first)
        viewModel.beginSelection(preselecting: first)
        #expect(viewModel.isSelecting)
        #expect(viewModel.selectedCount == 1)
        #expect(viewModel.isAllVisibleSelected == false)

        viewModel.toggleSelectAll()
        #expect(viewModel.selectedCount == 2)
        #expect(viewModel.isAllVisibleSelected)
        viewModel.toggleSelectAll()
        #expect(viewModel.selectedCount == 0)

        viewModel.toggleSelection(first)
        await viewModel.unfavoriteSelected()

        #expect(viewModel.isSelecting == false)
        #expect(viewModel.selectedCount == 0)
        #expect(viewModel.changeRevision == 1)
        #expect(Set(viewModel.favoriteItems.map(\.id)) == Set(["video-a", "video-b", "comic"]).subtracting([first.id]))
        #expect(try favorites.fetchFavoriteItemIDs().contains("comic"))
    }

    @Test func selectionEndsWhenTheLastFavoriteGoesAway() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let favorites: GRDBFavoriteRepository = GRDBFavoriteRepository(database: database)
        try favorites.restoreFavorite(item: Self.item(id: "comic", kind: .comic, hoursAgo: 1))
        let viewModel: FavoritesViewModel = Self.makeViewModel(database: database)
        await viewModel.load()
        viewModel.beginSelection()

        await viewModel.unfavorite(try #require(viewModel.favoriteItems.first))

        #expect(viewModel.isSelecting == false)
    }

    // MARK: - Fixtures

    private static func makeViewModel(database: AppDatabase) -> FavoritesViewModel {
        return FavoritesViewModel(
            persistenceCoordinator: FavoritesPersistenceCoordinator(
                loadFavoriteItemsUseCase: ToggleFavoriteUseCase(
                    favoriteRepository: GRDBFavoriteRepository(database: database)
                ),
                reconcileSourceSlotAssignmentsUseCase: ReconcileSourceSlotAssignmentsUseCase(
                    sourceRepository: GRDBSourceRepository(database: database)
                )
            ),
            now: { Self.noon }
        )
    }

    private static func item(
        id: String,
        kind: FavoriteContentKind = .comic,
        sourceID: String = "custom.source",
        hoursAgo: Double,
        snapshot: FavoriteSourceSnapshot? = nil
    ) -> FavoriteContentItem {
        // 中文注释：取整秒，避免数据库日期精度影响比较。
        let favoritedAt: Date = Date(
            timeIntervalSince1970: (Self.noon.timeIntervalSince1970 - hoursAgo * 3600).rounded()
        )
        return FavoriteContentItem(
            id: id,
            sourceID: sourceID,
            title: "Title \(id)",
            detailURL: "https://example.test/\(id)",
            coverURL: nil,
            kind: kind,
            latestText: nil,
            updatedAt: favoritedAt,
            favoritedAt: favoritedAt,
            listOrder: nil,
            listContext: nil,
            sourceSnapshot: snapshot
        )
    }
}
