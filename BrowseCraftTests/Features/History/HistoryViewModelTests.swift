import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft
import BrowseCraftDomain

// 中文注释：历史页重设计（`docs/design/History-Page-Redesign-Design.md`）的 ViewModel 测试——
// 真实 GRDB 历史与来源仓储，覆盖按作品删除与撤销写回、「看到哪里」与视频进度、来源状态。
@MainActor
struct HistoryViewModelTests {
    private typealias Harness = ViewModelTestHarness

    /// 本地日历上「今天中午」，分组判定不受测试运行时刻与时区影响。
    private static let noon: Date = Calendar.current.date(
        bySettingHour: 12,
        minute: 0,
        second: 0,
        of: Date()
    )!

    @Test func deletingAComicRemovesEveryChapterAndUndoWritesThemBack() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let comics: GRDBComicChapterHistoryRepository = GRDBComicChapterHistoryRepository(database: database)
        let chapter3: ComicChapterHistory = Self.comic(item: "dragon", chapter: 3, hoursAgo: 26, pageIndex: 4)
        let chapter4: ComicChapterHistory = Self.comic(item: "dragon", chapter: 4, hoursAgo: 25, pageIndex: 17)
        let other: ComicChapterHistory = Self.comic(item: "astronomy", chapter: 8, hoursAgo: 1)
        for history in [chapter3, chapter4, other] {
            try comics.save(history)
        }
        let viewModel: HistoryViewModel = Self.makeViewModel(database: database)

        await viewModel.load()

        // 中文注释：一行是一部作品，两章只显示最近一章；最近一条是继续卡片，不在列表里重复。
        #expect(viewModel.count(for: .comic) == 2)
        #expect(viewModel.continueEntry?.comicHistory?.comicItemID == "astronomy")
        let groups: [HistoryViewModel.DayGroup] = viewModel.dayGroups
        #expect(groups.map(\.day) == [.yesterday])
        let dragon: ReadingHistoryEntry = try #require(groups.first?.entries.first)
        #expect(dragon.comicHistory?.chapterKey == chapter4.chapterKey)

        await viewModel.delete(dragon)

        // 中文注释：删一行就删掉这部漫画的全部章节记录，重读后不会冒出上一章。
        #expect(viewModel.undoableEntry?.id == dragon.id)
        #expect(try comics.fetchHistory(userID: AppUser.localDefaultID).map(\.comicItemID) == ["astronomy"])
        await viewModel.load()
        #expect(viewModel.count(for: .comic) == 1)
        #expect(viewModel.dayGroups.isEmpty)

        await viewModel.delete(try #require(viewModel.continueEntry))
        #expect(viewModel.undoableEntry?.comicHistory?.comicItemID == "astronomy")
        // 中文注释：后一次删除的撤销只写回后一次的记录。
        await viewModel.undoDelete()

        #expect(viewModel.undoableEntry == nil)
        #expect(try comics.fetchHistory(userID: AppUser.localDefaultID).map(\.comicItemID) == ["astronomy"])

        // 中文注释：重新删 dragon 再撤销：两章原样写回，含原访问时间与页码，条目回到「昨天」分组。
        try comics.save(chapter3)
        try comics.save(chapter4)
        await viewModel.load()
        let reloaded: ReadingHistoryEntry = try #require(viewModel.dayGroups.first?.entries.first)
        await viewModel.delete(reloaded)
        await viewModel.undoDelete()

        let restored: [ComicChapterHistory] = try comics.fetchHistory(userID: AppUser.localDefaultID)
            .filter { $0.comicItemID == "dragon" }
            .sorted { $0.visitedAt < $1.visitedAt }
        #expect(restored.map(\.chapterKey) == [chapter3.chapterKey, chapter4.chapterKey])
        #expect(restored.map(\.lastPageIndex) == [4, 17])
        let latest: ComicChapterHistory = try #require(restored.last)
        #expect(abs(latest.visitedAt.timeIntervalSince(chapter4.visitedAt)) < 0.001)
        #expect(viewModel.dayGroups.map(\.day) == [.yesterday])
    }

    @Test func progressTextShowsWhereTheReaderLeftOff() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let videos: GRDBVideoWatchHistoryRepository = GRDBVideoWatchHistoryRepository(database: database)
        try videos.save(Self.video(vod: "watching", played: 1_260, duration: 2_700, hoursAgo: 1))
        try videos.save(Self.video(vod: "finished", played: 2_600, duration: 2_700, hoursAgo: 2))
        try videos.save(Self.video(vod: "no-duration", played: 3_720, duration: nil, hoursAgo: 3))
        try GRDBComicChapterHistoryRepository(database: database)
            .save(Self.comic(item: "paged", chapter: 92, hoursAgo: 4, pageIndex: 17))
        try GRDBBookReadingHistoryRepository(database: database).save(Self.book(chapter: "第三章", hoursAgo: 5))
        let viewModel: HistoryViewModel = Self.makeViewModel(database: database)

        await viewModel.load()

        let entries: [String: ReadingHistoryEntry] = Dictionary(
            uniqueKeysWithValues: viewModel.readingHistoryEntries.map { ($0.title, $0) }
        )
        let watching: ReadingHistoryEntry = try #require(entries["watching"])
        #expect(viewModel.progressText(for: watching) == "Episode 5 · " + String(
            format: NSLocalizedString("history_progress_watched_of", comment: ""), "21:00", "45:00"
        ))
        #expect(viewModel.playbackProgress(for: watching).map { abs($0 - 1_260.0 / 2_700.0) < 0.0001 } == true)

        // 中文注释：看到时长的 95% 及以后写「已看完」。
        let finished: ReadingHistoryEntry = try #require(entries["finished"])
        #expect(viewModel.progressText(for: finished)
            == "Episode 5 · " + NSLocalizedString("history_progress_finished", comment: ""))

        // 中文注释：没有时长只写看到哪里，不画进度条；超过一小时带小时位。
        let noDuration: ReadingHistoryEntry = try #require(entries["no-duration"])
        #expect(viewModel.progressText(for: noDuration) == "Episode 5 · " + String(
            format: NSLocalizedString("history_progress_watched", comment: ""), "1:02:00"
        ))
        #expect(viewModel.playbackProgress(for: noDuration) == nil)

        // 中文注释：漫画页码是 0 起的索引，显示时加一。
        let paged: ReadingHistoryEntry = try #require(entries["paged"])
        #expect(viewModel.progressText(for: paged) == "#92 · " + String(
            format: NSLocalizedString("history_progress_page", comment: ""), 18
        ))

        let book: ReadingHistoryEntry = try #require(entries["book"])
        #expect(viewModel.progressText(for: book)
            == String(format: NSLocalizedString("history_progress_read_to", comment: ""), "第三章"))

        // 中文注释：筛选计数；三类一直显示，没有记录的类型为 0。
        #expect(viewModel.count(for: .video) == 3)
        viewModel.kindFilter = .book
        #expect(viewModel.continueEntry?.title == "book")
        #expect(viewModel.dayGroups.isEmpty)
    }

    @Test func sourceStateFollowsTheSourceBehindEachEntry() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let sourceRepository: GRDBSourceRepository = GRDBSourceRepository(database: database)
        let active: Source = try Harness.makeComicSource(id: "custom.active", name: "Active")
        var paused: Source = try Harness.makeComicSource(id: "custom.paused", name: "Paused")
        try sourceRepository.saveSource(active)
        paused.enabled = false
        try sourceRepository.saveSource(paused)
        let deleted: Source = try Harness.makeComicSource(id: "custom.deleted", name: "Deleted")

        let comics: GRDBComicChapterHistoryRepository = GRDBComicChapterHistoryRepository(database: database)
        try comics.save(Self.comic(item: "on-active", chapter: 1, hoursAgo: 1, sourceID: active.id))
        try comics.save(Self.comic(item: "on-paused", chapter: 1, hoursAgo: 2, sourceID: paused.id))
        try comics.save(Self.comic(
            item: "on-deleted", chapter: 1, hoursAgo: 3, sourceID: deleted.id, snapshot: SourceSnapshot(source: deleted)
        ))
        try comics.save(Self.comic(item: "on-unknown", chapter: 1, hoursAgo: 4, sourceID: "custom.gone"))
        try GRDBTemporaryResourceHistoryRepository(database: database).save(TemporaryResourceHistory(
            userID: AppUser.localDefaultID,
            kind: .comic,
            title: "temporary",
            resourceURL: URL(string: "https://temp.example.test/read/1")!,
            coverURL: nil,
            sourcePageURL: nil,
            matchedKeyword: nil,
            videoPlaybackKind: nil,
            visitedAt: Self.date(hoursAgo: 5)
        ))
        let viewModel: HistoryViewModel = Self.makeViewModel(database: database)

        await viewModel.load()

        let entries: [String: ReadingHistoryEntry] = Dictionary(
            uniqueKeysWithValues: viewModel.readingHistoryEntries.map { ($0.title, $0) }
        )
        #expect(viewModel.sourceState(for: try #require(entries["on-active"])) == .available)
        #expect(viewModel.sourceState(for: try #require(entries["on-paused"])) == .paused)
        let onDeleted: ReadingHistoryEntry = try #require(entries["on-deleted"])
        #expect(viewModel.sourceState(for: onDeleted) == .deleted)
        #expect(viewModel.sourceName(for: onDeleted) == "Deleted")
        let onUnknown: ReadingHistoryEntry = try #require(entries["on-unknown"])
        #expect(viewModel.sourceState(for: onUnknown) == .unknown)
        #expect(viewModel.source(for: onUnknown) == nil)
        #expect(viewModel.sourceName(for: onUnknown) == NSLocalizedString("favorites_unknown_source", comment: ""))
        // 中文注释：临时资源按自身类型归入漫画，第三行是主机名。
        let temporary: ReadingHistoryEntry = try #require(entries["temporary"])
        #expect(viewModel.sourceState(for: temporary) == .temporary)
        #expect(viewModel.sourceName(for: temporary) == "temp.example.test")
        #expect(viewModel.count(for: .comic) == 5)
    }

    // MARK: - Fixtures

    private static func makeViewModel(database: AppDatabase) -> HistoryViewModel {
        let comics: GRDBComicChapterHistoryRepository = GRDBComicChapterHistoryRepository(database: database)
        let videos: GRDBVideoWatchHistoryRepository = GRDBVideoWatchHistoryRepository(database: database)
        let books: GRDBBookReadingHistoryRepository = GRDBBookReadingHistoryRepository(database: database)
        let temporaries: GRDBTemporaryResourceHistoryRepository = GRDBTemporaryResourceHistoryRepository(database: database)
        return HistoryViewModel(
            persistenceCoordinator: HistoryPersistenceCoordinator(
                loadReadingHistoryEntriesUseCase: LoadReadingHistoryEntriesUseCase(
                    comicRepository: comics,
                    videoRepository: videos,
                    bookRepository: books,
                    temporaryRepository: temporaries
                ),
                deleteReadingHistoryEntryUseCase: DeleteReadingHistoryEntryUseCase(
                    comicRepository: comics,
                    videoRepository: videos,
                    bookRepository: books,
                    temporaryRepository: temporaries
                ),
                restoreReadingHistoryUseCase: RestoreReadingHistoryUseCase(
                    comicRepository: comics,
                    videoRepository: videos,
                    bookRepository: books,
                    temporaryRepository: temporaries
                ),
                reconcileSourceSlotAssignmentsUseCase: ReconcileSourceSlotAssignmentsUseCase(
                    sourceRepository: GRDBSourceRepository(database: database)
                )
            ),
            videoPlayerViewModelFactory: { _, _ in
                fatalError("历史页测试不打开播放器")
            },
            now: { Self.noon }
        )
    }

    /// 中文注释：取整秒，避免数据库日期精度影响比较。
    private static func date(hoursAgo: Double) -> Date {
        return Date(timeIntervalSince1970: (Self.noon.timeIntervalSince1970 - hoursAgo * 3600).rounded())
    }

    private static func comic(
        item: String,
        chapter: Int,
        hoursAgo: Double,
        pageIndex: Int? = nil,
        sourceID: String = "custom.source",
        snapshot: SourceSnapshot? = nil
    ) -> ComicChapterHistory {
        let detailURL: URL = URL(string: "https://comic.example.test/\(item)")!
        return ComicChapterHistory(
            userID: AppUser.localDefaultID,
            sourceID: sourceID,
            comicItemID: item,
            comicTitle: item,
            chapterID: "chapter-\(chapter)",
            chapterKey: "chapter-\(chapter)",
            chapterURL: detailURL.appendingPathComponent("chapter-\(chapter)"),
            chapterTitle: "#\(chapter)",
            visitedAt: Self.date(hoursAgo: hoursAgo),
            coverURL: nil,
            lastPageIndex: pageIndex,
            sourceSnapshot: snapshot
        )
    }

    private static func video(vod: String, played: TimeInterval, duration: TimeInterval?, hoursAgo: Double) -> VideoWatchHistory {
        let detailURL: URL = URL(string: "https://video.example.test/\(vod)")!
        let visitedAt: Date = Self.date(hoursAgo: hoursAgo)
        return VideoWatchHistory(
            userID: AppUser.localDefaultID,
            sourceID: "custom.video",
            vodID: vod,
            videoTitle: vod,
            episodeTitle: "Episode 5",
            episodeKey: "episode-5",
            sourceIndex: 0,
            episodeIndex: 4,
            detailURL: detailURL,
            playPageURL: detailURL.appendingPathComponent("episode-5"),
            candidateMediaKind: .unknown,
            playbackStatus: .pageOnly,
            coverURL: nil,
            sourceName: "Video Site",
            lastPlaybackTime: played,
            duration: duration,
            visitedAt: visitedAt,
            updatedAt: visitedAt
        )
    }

    private static func book(chapter: String, hoursAgo: Double) -> BookReadingHistory {
        return BookReadingHistory(
            userID: AppUser.localDefaultID,
            sourceID: "custom.book",
            detailURL: "https://book.example.test/book",
            bookItemID: "https://book.example.test/book",
            bookTitle: "book",
            coverURL: nil,
            chapterTitle: chapter,
            chapterURL: nil,
            visitedAt: Self.date(hoursAgo: hoursAgo)
        )
    }
}
