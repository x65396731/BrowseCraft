import BrowseCraftDomain
import Foundation

struct LibraryPersistenceSnapshot: Sendable {
    let sources: [Source]
    let favoriteItemIDs: Set<String>
    let libraryState: UserLibraryState?
}

struct LibraryFavoriteMutation: Sendable {
    let item: ContentItem
    let source: Source?
    let favoritedAt: Date
}

struct UserLibraryStateTransfer: Sendable {
    let value: UserLibraryState
}

/// 将 Library 的同步 Repository 调用隔离到专用 actor，ViewModel 只在 MainActor 应用结果。
actor LibraryPersistenceCoordinator {
    private let syncBuiltInSourcesUseCase: SyncBuiltInSourcesUseCase
    private let reconcileSourceSlotAssignmentsUseCase:
        ReconcileSourceSlotAssignmentsUseCase
    private let toggleFavoriteUseCase: ToggleFavoriteUseCase
    private let loadUserLibraryStateUseCase: LoadUserLibraryStateUseCase
    private let saveUserLibraryStateUseCase: SaveUserLibraryStateUseCase
    /// 中文注释：库页「上次看到」瓷砖只读视频历史（`docs/design/Library-Video-Page-Redesign-Design.md` 第六节）；
    /// 测试替身不给时瓷砖永远不出现。
    private let videoWatchHistoryRepository: VideoWatchHistoryRepository?
    /// 中文注释：漫画来源的「上次读到」瓷砖与封面进度角标读漫画章节历史（`docs/design/Library-Comic-Page-Redesign-Design.md`
    /// 第六、九节）；测试替身不给时两者都不出现。
    private let comicChapterHistoryRepository: ComicChapterHistoryRepository?
    /// 中文注释：读书来源的「上次读到」瓷砖与行的「读到哪」读读书历史，瓷砖进度条读进度表
    /// （`docs/design/Library-Book-Page-Redesign-Design.md` 第六、九节）；测试替身不给时都不出现。
    private let bookReadingHistoryRepository: BookReadingHistoryRepository?
    private let bookReadingProgressRepository: BookReadingProgressRepository?

    init(
        syncBuiltInSourcesUseCase: SyncBuiltInSourcesUseCase,
        reconcileSourceSlotAssignmentsUseCase: ReconcileSourceSlotAssignmentsUseCase,
        toggleFavoriteUseCase: ToggleFavoriteUseCase,
        loadUserLibraryStateUseCase: LoadUserLibraryStateUseCase,
        saveUserLibraryStateUseCase: SaveUserLibraryStateUseCase,
        videoWatchHistoryRepository: VideoWatchHistoryRepository? = nil,
        comicChapterHistoryRepository: ComicChapterHistoryRepository? = nil,
        bookReadingHistoryRepository: BookReadingHistoryRepository? = nil,
        bookReadingProgressRepository: BookReadingProgressRepository? = nil
    ) {
        self.syncBuiltInSourcesUseCase = syncBuiltInSourcesUseCase
        self.reconcileSourceSlotAssignmentsUseCase = reconcileSourceSlotAssignmentsUseCase
        self.toggleFavoriteUseCase = toggleFavoriteUseCase
        self.loadUserLibraryStateUseCase = loadUserLibraryStateUseCase
        self.saveUserLibraryStateUseCase = saveUserLibraryStateUseCase
        self.videoWatchHistoryRepository = videoWatchHistoryRepository
        self.comicChapterHistoryRepository = comicChapterHistoryRepository
        self.bookReadingHistoryRepository = bookReadingHistoryRepository
        self.bookReadingProgressRepository = bookReadingProgressRepository
    }

    /// 当前来源最近一条视频历史：按来源过滤、取更新时间最晚的一条。没有仓储或没有记录为 nil。
    func latestVideoHistory(userID: String, sourceID: String) throws -> VideoWatchHistory? {
        guard let repository: VideoWatchHistoryRepository = self.videoWatchHistoryRepository else {
            return nil
        }
        return try repository.fetchHistory(userID: userID)
            .filter { history in history.sourceID == sourceID }
            .max { lhs, rhs in lhs.updatedAt < rhs.updatedAt }
    }

    /// 当前来源读过的全部漫画章节，访问时间最近的在前。一次读全部：瓷砖取第一条，进度角标按作品各取最近一条。
    func comicChapterHistories(userID: String, sourceID: String) throws -> [ComicChapterHistory] {
        guard let repository: ComicChapterHistoryRepository = self.comicChapterHistoryRepository else {
            return []
        }
        return try repository.fetchHistory(userID: userID)
            .filter { history in history.sourceID == sourceID }
            .sorted { lhs, rhs in lhs.visitedAt > rhs.visitedAt }
    }

    /// 当前来源读过的全部书，访问时间最近的在前（一本书一条）。瓷砖取第一条，行的「读到哪」按 `bookItemID` 对上。
    func bookReadingHistories(userID: String, sourceID: String) throws -> [BookReadingHistory] {
        guard let repository: BookReadingHistoryRepository = self.bookReadingHistoryRepository else {
            return []
        }
        return try repository.fetchHistory(userID: userID)
            .filter { history in history.sourceID == sourceID }
            .sorted { lhs, rhs in lhs.visitedAt > rhs.visitedAt }
    }

    /// 一本书的全书进度（0…1，Readium 写的 `totalProgression`）；只给瓷砖那一本用，没有仓储或没有记录为 nil。
    func bookReadingProgression(userID: String, sourceID: String, detailURL: String) throws -> Double? {
        guard let repository: BookReadingProgressRepository = self.bookReadingProgressRepository else {
            return nil
        }
        let bookID: UUID = SiteBookIdentity.bookID(sourceID: sourceID, detailURL: detailURL)
        return try repository.fetchProgress(bookID: bookID, userID: userID)?.totalProgression
    }

    func load(userID: String, selectedSourceID: String?) throws -> LibraryPersistenceSnapshot {
        try self.syncBuiltInSourcesUseCase.execute()
        return LibraryPersistenceSnapshot(
            sources: try self.reconcileSourceSlotAssignmentsUseCase.execute(),
            favoriteItemIDs: try self.toggleFavoriteUseCase.loadFavoriteItemIDs(
                sourceID: selectedSourceID
            ),
            libraryState: try self.loadUserLibraryStateUseCase.execute(userID: userID)
        )
    }

    func favoriteItemIDs(sourceID: String?) throws -> Set<String> {
        return try self.toggleFavoriteUseCase.loadFavoriteItemIDs(sourceID: sourceID)
    }

    func toggleFavorite(_ mutation: LibraryFavoriteMutation) throws -> Set<String> {
        return try self.toggleFavoriteUseCase.execute(
            item: mutation.item,
            source: mutation.source,
            favoritedAt: mutation.favoritedAt
        )
    }

    func save(_ state: UserLibraryStateTransfer) throws {
        try self.saveUserLibraryStateUseCase.execute(state: state.value)
    }
}
