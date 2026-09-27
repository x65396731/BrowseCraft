import BrowseCraftDomain
import BrowseCraftRuntime
import Foundation
import ReadiumNavigator
import ReadiumShared
import Testing
@testable import BrowseCraft

// 中文注释：阅读器视图模型：位置节流后只落最新一条、flush 立即落、书签往返；打开一本真实夹具 EPUB 走到 ready。

@MainActor
struct BookReaderViewModelTests {
    @Test func locationChangesAreThrottledToTheLatest() async throws {
        let progress: ReaderInMemoryProgressRepository = ReaderInMemoryProgressRepository()
        let viewModel: BookReaderViewModel = Self.makeViewModel(progress: progress, throttleNanoseconds: 50_000_000)

        viewModel.navigatorDidChangeLocation(Self.locator(href: "/c1", progression: 0.1))
        viewModel.navigatorDidChangeLocation(Self.locator(href: "/c1", progression: 0.2))
        viewModel.navigatorDidChangeLocation(Self.locator(href: "/c2", progression: 0.5))
        #expect(progress.saved.isEmpty)

        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(progress.saved.count == 1)
        #expect(progress.saved.last?.totalProgression == 0.5)
        let restored: Locator = try #require(BookReaderViewModel.locator(fromJSON: progress.saved.last!.locatorJSON))
        #expect(restored.href.string.hasSuffix("/c2"))
    }

    @Test func flushWritesImmediately() async throws {
        let progress: ReaderInMemoryProgressRepository = ReaderInMemoryProgressRepository()
        let viewModel: BookReaderViewModel = Self.makeViewModel(progress: progress, throttleNanoseconds: 60_000_000_000)

        viewModel.navigatorDidChangeLocation(Self.locator(href: "/c3", progression: 0.9))
        viewModel.flush()

        #expect(progress.saved.count == 1)
        #expect(progress.saved.last?.totalProgression == 0.9)
    }

    @Test func bookmarksRoundTripThroughLocatorJSON() async throws {
        let viewModel: BookReaderViewModel = Self.makeViewModel(progress: ReaderInMemoryProgressRepository(), throttleNanoseconds: 60_000_000_000)
        viewModel.navigatorDidChangeLocation(Self.locator(href: "/c1", progression: 0.3, title: "Chapter 1"))

        await viewModel.addBookmarkAtCurrentLocation()

        #expect(viewModel.bookmarks.count == 1)
        #expect(viewModel.bookmarks.first?.title == "Chapter 1")
        let restored: Locator = try #require(BookReaderViewModel.locator(fromJSON: viewModel.bookmarks[0].locatorJSON))
        #expect(restored.locations.totalProgression == 0.3)
        await viewModel.removeBookmark(viewModel.bookmarks[0])
        #expect(viewModel.bookmarks.isEmpty)
    }

    @Test func openingRealEPUBReachesReadyWithContents() async throws {
        let fixture: URL = try #require(Bundle(for: ReaderFixtureMarker.self).url(forResource: "fixture-book", withExtension: "epub"))
        let root: URL = FileManager.default.temporaryDirectory.appendingPathComponent("BookReaderVMTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store: FileSystemBookFileStore = FileSystemBookFileStore(rootDirectory: root)
        let bookID: UUID = UUID()
        let stored: StoredBookFile = try await store.storeBookFile(from: fixture, bookID: bookID, fileExtension: "epub")
        let book: LocalBook = LocalBook(
            id: bookID, userID: "u1", title: "Fixture Book", author: nil, format: .epub, fileRelativePath: stored.relativePath,
            coverRelativePath: nil, fileSHA256: stored.sha256, byteCount: stored.byteCount, importedAt: Date(), lastOpenedAt: nil
        )
        let books: ReaderInMemoryLocalBookRepository = ReaderInMemoryLocalBookRepository(book: book)
        let progress: ReaderInMemoryProgressRepository = ReaderInMemoryProgressRepository()
        let bookmarks: ReaderInMemoryBookmarkRepository = ReaderInMemoryBookmarkRepository()
        let viewModel: BookReaderViewModel = BookReaderViewModel(
            subject: .local(book),
            userID: "u1",
            openLocalUseCase: OpenLocalBookUseCase(repository: books, progressRepository: progress, fileStore: store, opener: ReadiumBookPublicationOpener()),
            loadSitePublicationUseCase: nil,
            sitePublicationBuilder: ReadiumSitePublicationBuilderAdapter(),
            loadProgressUseCase: LoadBookReadingProgressUseCase(progressRepository: progress),
            saveProgressUseCase: SaveBookReadingProgressUseCase(progressRepository: progress),
            addBookmarkUseCase: AddBookBookmarkUseCase(repository: bookmarks),
            listBookmarksUseCase: ListBookBookmarksUseCase(repository: bookmarks),
            removeBookmarkUseCase: RemoveBookBookmarkUseCase(repository: bookmarks)
        )

        await viewModel.open()

        #expect(viewModel.state == .ready)
        #expect(viewModel.publication?.readingOrder.count == 2)
        #expect(viewModel.tableOfContents.map { $0.title } == ["Chapter 1", "Chapter 2"])
        #expect(viewModel.initialLocator == nil)
    }

    // 中文注释：站点有声作品：详情 → manifest（17 条 mp3）→ AudioNavigator 建成、起点是点开的那一章；不触发播放（不碰网络）。
    @Test func openingSiteAudiobookBuildsAnAudioNavigator() async throws {
        let loader: FixturePageContentLoader = FixturePageContentLoader(fixtures: [
            "https://www.loyalbooks.com/book/tom-sawyer-by-mark-twain": "loyalbooks-detail-tom-sawyer",
        ])
        let source: Source = try BookRuntimeFixtures.source(fixture: "loyalbooks-catalog")
        let runtime: BookSourceRuntime = try BookSourceRuntimeFactory(pageContentLoader: loader).makeRuntime(source: source)
        let item: ContentItem = ContentItem(
            id: "tom-sawyer", sourceId: source.id, title: "Tom Sawyer", detailURL: "https://www.loyalbooks.com/book/tom-sawyer-by-mark-twain",
            coverURL: nil, type: .article, latestText: nil
        )
        let progress: ReaderInMemoryProgressRepository = ReaderInMemoryProgressRepository()
        let bookmarks: ReaderInMemoryBookmarkRepository = ReaderInMemoryBookmarkRepository()
        let viewModel: BookReaderViewModel = BookReaderViewModel(
            subject: .site(SiteBookChapterSelection(source: source, item: item, chapterURL: nil, chapterTitle: nil)),
            userID: "u1",
            openLocalUseCase: nil,
            loadSitePublicationUseCase: LoadBookPublicationUseCase(runtimeResolver: SingleRuntimeResolver(runtime: runtime)),
            sitePublicationBuilder: ReadiumSitePublicationBuilderAdapter(),
            loadProgressUseCase: LoadBookReadingProgressUseCase(progressRepository: progress),
            saveProgressUseCase: SaveBookReadingProgressUseCase(progressRepository: progress),
            addBookmarkUseCase: AddBookBookmarkUseCase(repository: bookmarks),
            listBookmarksUseCase: ListBookBookmarksUseCase(repository: bookmarks),
            removeBookmarkUseCase: RemoveBookBookmarkUseCase(repository: bookmarks)
        )

        await viewModel.open()

        #expect(viewModel.state == .ready)
        #expect(viewModel.isAudiobook)
        #expect(viewModel.audioNavigator != nil)
        #expect(viewModel.publication?.readingOrder.count == 17)
        #expect(viewModel.tableOfContents.count == 17)
        #expect(viewModel.initialLocator == nil, "没点具体章节、没有续听位置时从头开始")

        let secondChapter: URL = try #require(viewModel.publication?.readingOrder[1].url().url)
        let chapterViewModel: BookReaderViewModel = BookReaderViewModel(
            subject: .site(SiteBookChapterSelection(source: source, item: item, chapterURL: secondChapter, chapterTitle: nil)),
            userID: "u1",
            openLocalUseCase: nil,
            loadSitePublicationUseCase: LoadBookPublicationUseCase(runtimeResolver: SingleRuntimeResolver(runtime: runtime)),
            sitePublicationBuilder: ReadiumSitePublicationBuilderAdapter(),
            loadProgressUseCase: LoadBookReadingProgressUseCase(progressRepository: progress),
            saveProgressUseCase: SaveBookReadingProgressUseCase(progressRepository: progress),
            addBookmarkUseCase: AddBookBookmarkUseCase(repository: bookmarks),
            listBookmarksUseCase: ListBookBookmarksUseCase(repository: bookmarks),
            removeBookmarkUseCase: RemoveBookBookmarkUseCase(repository: bookmarks)
        )
        await chapterViewModel.open()
        #expect(chapterViewModel.initialLocator?.href.string == secondChapter.absoluteString)
        #expect(chapterViewModel.initialLocator?.mediaType == .mp3)
    }

    // 中文注释：站点书进历史：打开写一条（还没有位置时记第一章），换章后落进度更新同一条；
    // 从历史重建的阅读主体不带章节、作品身份与原来一致（续读位置与书签才接得上）。
    @Test func openingSiteBookRecordsOneHistoryRowThatFollowsTheChapter() async throws {
        let loader: FixturePageContentLoader = FixturePageContentLoader(fixtures: [
            "https://www.loyalbooks.com/book/tom-sawyer-by-mark-twain": "loyalbooks-detail-tom-sawyer",
        ])
        let source: Source = try BookRuntimeFixtures.source(fixture: "loyalbooks-catalog")
        let runtime: BookSourceRuntime = try BookSourceRuntimeFactory(pageContentLoader: loader).makeRuntime(source: source)
        let item: ContentItem = ContentItem(
            id: "tom-sawyer", sourceId: source.id, title: "Tom Sawyer", detailURL: "https://www.loyalbooks.com/book/tom-sawyer-by-mark-twain",
            coverURL: nil, type: .article, latestText: nil
        )
        let progress: ReaderInMemoryProgressRepository = ReaderInMemoryProgressRepository()
        let bookmarks: ReaderInMemoryBookmarkRepository = ReaderInMemoryBookmarkRepository()
        let histories: ReaderInMemoryHistoryRepository = ReaderInMemoryHistoryRepository()
        let viewModel: BookReaderViewModel = BookReaderViewModel(
            subject: .site(SiteBookChapterSelection(source: source, item: item, chapterURL: nil, chapterTitle: nil)),
            userID: "u1",
            openLocalUseCase: nil,
            loadSitePublicationUseCase: LoadBookPublicationUseCase(runtimeResolver: SingleRuntimeResolver(runtime: runtime)),
            sitePublicationBuilder: ReadiumSitePublicationBuilderAdapter(),
            loadProgressUseCase: LoadBookReadingProgressUseCase(progressRepository: progress),
            saveProgressUseCase: SaveBookReadingProgressUseCase(progressRepository: progress),
            addBookmarkUseCase: AddBookBookmarkUseCase(repository: bookmarks),
            listBookmarksUseCase: ListBookBookmarksUseCase(repository: bookmarks),
            removeBookmarkUseCase: RemoveBookBookmarkUseCase(repository: bookmarks),
            saveHistoryUseCase: SaveBookReadingHistoryUseCase(repository: histories),
            throttleNanoseconds: 60_000_000_000
        )

        await viewModel.open()

        #expect(viewModel.state == .ready)
        let readingOrder: [Link] = try #require(viewModel.publication?.readingOrder)
        #expect(histories.rows.count == 1)
        let opened: BookReadingHistory = try #require(histories.rows.last)
        #expect(opened.sourceID == source.id)
        #expect(opened.detailURL == item.detailURL)
        #expect(opened.bookItemID == item.id)
        #expect(opened.bookTitle == viewModel.title)
        #expect(opened.chapterURL == readingOrder[0].url().url)
        #expect(opened.chapterTitle != nil)
        #expect(opened.sourceSnapshot?.id == source.id)

        let third: URL = readingOrder[2].url().url
        viewModel.navigatorDidChangeLocation(Locator(href: AnyURL(url: third), mediaType: .mp3, title: nil))
        viewModel.flush()

        #expect(histories.rows.count == 1, "一本书一条")
        let moved: BookReadingHistory = try #require(histories.rows.last)
        #expect(moved.chapterURL == third)
        #expect(moved.chapterTitle != nil)
        #expect(moved.chapterTitle != opened.chapterTitle)

        let reopened: SiteBookChapterSelection = SiteBookChapterSelection(history: moved, source: source)
        #expect(reopened.chapterURL == nil)
        #expect(BookReaderSubject.site(reopened).bookID == viewModel.bookID)
    }

    // 中文注释：站点文字书的广告积分（30.8）：按当前位置所在章计分、同一章只计一次；两章 +100 满额、广告没播出来积分保留。
    @Test func siteTextBookAwardsAdPointsOncePerChapter() async throws {
        let loader: FixturePageContentLoader = FixturePageContentLoader(fixtures: [
            "https://www.biquhua.com/book/0/110/": "biquhua-detail-110",
        ])
        let source: Source = try BookRuntimeFixtures.source(fixture: "biquhua-catalog")
        let runtime: BookSourceRuntime = try BookSourceRuntimeFactory(pageContentLoader: loader).makeRuntime(source: source)
        let item: ContentItem = ContentItem(
            id: "110", sourceId: source.id, title: "迷魂阵", detailURL: "https://www.biquhua.com/book/0/110/",
            coverURL: nil, type: .article, latestText: nil
        )
        let points: AdPointsFixture = try AdPointsFixture()
        let viewModel: BookReaderViewModel = Self.makeSiteViewModel(source: source, item: item, runtime: runtime, adPoints: points.coordinator)

        await viewModel.open()
        #expect(viewModel.state == .ready)
        #expect(viewModel.isAudiobook == false)
        let readingOrder: [Link] = try #require(viewModel.publication?.readingOrder)
        #expect(readingOrder.count >= 2)
        // 没点具体章节：打开时还没有位置，不计
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(try points.pendingPoints() == 0)

        let first: URL = readingOrder[0].url().url
        viewModel.navigatorDidChangeLocation(Locator(href: AnyURL(url: first), mediaType: .xhtml, title: nil))
        #expect(await ViewModelTestHarness.waitUntil { (try? points.pendingPoints()) == AdPointRule.bookChapterPoints })

        // 同一章翻页不再计
        viewModel.navigatorDidChangeLocation(Locator(href: AnyURL(url: first), mediaType: .xhtml, title: nil, locations: Locator.Locations(progression: 0.5)))
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(try points.pendingPoints() == AdPointRule.bookChapterPoints)
        #expect(viewModel.shouldPlayAd == false)

        let second: URL = readingOrder[1].url().url
        viewModel.navigatorDidChangeLocation(Locator(href: AnyURL(url: second), mediaType: .xhtml, title: nil))
        #expect(await ViewModelTestHarness.waitUntil { viewModel.shouldPlayAd })
        #expect(try points.pendingPoints() == AdPointRule.threshold)

        viewModel.markAdPlaybackHandled(outcome: .presented(.failed("no fill")))
        #expect(viewModel.shouldPlayAd == false)
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(try points.pendingPoints() == AdPointRule.threshold, "广告没播出来，积分保留")

        viewModel.markAdPlaybackHandled(outcome: .presented(.completed))
        #expect(await ViewModelTestHarness.waitUntil { (try? points.pendingPoints()) == 0 })
    }

    // 中文注释：有声书只计实际播放（30.8）：按 AudioNavigator 上报的时间差累计，暂停与大跳变不计；满 600 秒 +50。
    @Test func audiobookAwardsAdPointsByPlayedTime() async throws {
        let loader: FixturePageContentLoader = FixturePageContentLoader(fixtures: [
            "https://www.loyalbooks.com/book/tom-sawyer-by-mark-twain": "loyalbooks-detail-tom-sawyer",
        ])
        let source: Source = try BookRuntimeFixtures.source(fixture: "loyalbooks-catalog")
        let runtime: BookSourceRuntime = try BookSourceRuntimeFactory(pageContentLoader: loader).makeRuntime(source: source)
        let item: ContentItem = ContentItem(
            id: "tom-sawyer", sourceId: source.id, title: "Tom Sawyer", detailURL: "https://www.loyalbooks.com/book/tom-sawyer-by-mark-twain",
            coverURL: nil, type: .article, latestText: nil
        )
        let points: AdPointsFixture = try AdPointsFixture()
        let viewModel: BookReaderViewModel = Self.makeSiteViewModel(source: source, item: item, runtime: runtime, adPoints: points.coordinator)

        await viewModel.open()
        #expect(viewModel.isAudiobook)

        // 第一次上报只定基准；暂停时的上报不计；拖动 200 秒的一步不计
        viewModel.audioPlaybackDidChange(MediaPlaybackInfo(resourceIndex: 0, state: .playing, time: 0, duration: 3_600))
        var time: Double = 0
        for _ in 0..<599 {
            time += 1
            viewModel.audioPlaybackDidChange(MediaPlaybackInfo(resourceIndex: 0, state: .playing, time: time, duration: 3_600))
        }
        time += 200
        viewModel.audioPlaybackDidChange(MediaPlaybackInfo(resourceIndex: 0, state: .playing, time: time, duration: 3_600))
        time += 1
        viewModel.audioPlaybackDidChange(MediaPlaybackInfo(resourceIndex: 0, state: .paused, time: time, duration: 3_600))
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(try points.pendingPoints() == 0)

        time += 1
        viewModel.audioPlaybackDidChange(MediaPlaybackInfo(resourceIndex: 0, state: .playing, time: time, duration: 3_600))
        #expect(await ViewModelTestHarness.waitUntil { (try? points.pendingPoints()) == AdPointRule.audiobookPoints })
        #expect(viewModel.shouldPlayAd == false)
    }

    // MARK: - Helpers

    /// 中文注释：真实 GRDB 库上的积分协调器；活动用户是随机 UUID、行已插好。
    private struct AdPointsFixture {
        let coordinator: ReadingActivityPersistenceCoordinator
        private let repository: GRDBAppUserRepository
        private let userID: String

        init() throws {
            let database: AppDatabase = try ViewModelTestHarness.makeDatabase()
            let userID: UUID = UUID()
            try ViewModelTestHarness.insertUser(userID, into: database)
            let activeAppUser: ActiveAppUserStore = ActiveAppUserStore(initialUserID: userID)
            self.repository = GRDBAppUserRepository(database: database)
            self.userID = userID.uuidString
            self.coordinator = ReadingActivityPersistenceCoordinator(
                comicRepository: GRDBComicChapterHistoryRepository(database: database),
                videoRepository: GRDBVideoWatchHistoryRepository(database: database),
                appUserRepository: self.repository,
                activeAppUser: activeAppUser
            )
        }

        func pendingPoints() throws -> Int {
            return try self.repository.fetchUser(id: self.userID)?.pendingAdPoints ?? -1
        }
    }

    private static func makeSiteViewModel(
        source: Source,
        item: ContentItem,
        runtime: BookSourceRuntime,
        adPoints: ReadingActivityPersistenceCoordinator
    ) -> BookReaderViewModel {
        let progress: ReaderInMemoryProgressRepository = ReaderInMemoryProgressRepository()
        let bookmarks: ReaderInMemoryBookmarkRepository = ReaderInMemoryBookmarkRepository()
        return BookReaderViewModel(
            subject: .site(SiteBookChapterSelection(source: source, item: item, chapterURL: nil, chapterTitle: nil)),
            userID: "u1",
            openLocalUseCase: nil,
            loadSitePublicationUseCase: LoadBookPublicationUseCase(runtimeResolver: SingleRuntimeResolver(runtime: runtime)),
            sitePublicationBuilder: ReadiumSitePublicationBuilderAdapter(),
            loadProgressUseCase: LoadBookReadingProgressUseCase(progressRepository: progress),
            saveProgressUseCase: SaveBookReadingProgressUseCase(progressRepository: progress),
            addBookmarkUseCase: AddBookBookmarkUseCase(repository: bookmarks),
            listBookmarksUseCase: ListBookBookmarksUseCase(repository: bookmarks),
            removeBookmarkUseCase: RemoveBookBookmarkUseCase(repository: bookmarks),
            adPoints: adPoints,
            throttleNanoseconds: 60_000_000_000
        )
    }

    private static func makeViewModel(progress: ReaderInMemoryProgressRepository, throttleNanoseconds: UInt64) -> BookReaderViewModel {
        let book: LocalBook = LocalBook(
            id: UUID(), userID: "u1", title: "T", author: nil, format: .epub, fileRelativePath: "x.epub",
            coverRelativePath: nil, fileSHA256: "s", byteCount: 1, importedAt: Date(), lastOpenedAt: nil
        )
        let bookmarks: ReaderInMemoryBookmarkRepository = ReaderInMemoryBookmarkRepository()
        return BookReaderViewModel(
            subject: .local(book),
            userID: "u1",
            openLocalUseCase: OpenLocalBookUseCase(
                repository: ReaderInMemoryLocalBookRepository(book: book),
                progressRepository: progress,
                fileStore: ReaderStubFileStore(),
                opener: ReaderFailingOpener()
            ),
            loadSitePublicationUseCase: nil,
            sitePublicationBuilder: ReadiumSitePublicationBuilderAdapter(),
            loadProgressUseCase: LoadBookReadingProgressUseCase(progressRepository: progress),
            saveProgressUseCase: SaveBookReadingProgressUseCase(progressRepository: progress),
            addBookmarkUseCase: AddBookBookmarkUseCase(repository: bookmarks),
            listBookmarksUseCase: ListBookBookmarksUseCase(repository: bookmarks),
            removeBookmarkUseCase: RemoveBookBookmarkUseCase(repository: bookmarks),
            throttleNanoseconds: throttleNanoseconds
        )
    }

    private static func locator(href: String, progression: Double, title: String? = nil) -> Locator {
        return Locator(
            href: AnyURL(string: href)!,
            mediaType: .xhtml,
            title: title,
            locations: Locator.Locations(progression: progression, totalProgression: progression)
        )
    }
}

private final class ReaderFixtureMarker {}

private struct ReaderFailingOpener: BookPublicationOpening {
    func openPublication(fileURL: URL, format: LocalBookFormat) async throws -> BookPublicationHandle {
        throw BookPublicationOpenError.parsingFailed(reason: "not-used")
    }
}

private struct ReaderStubFileStore: BookFileStoring {
    func storeBookFile(from sourceURL: URL, bookID: UUID, fileExtension: String) async throws -> StoredBookFile {
        return StoredBookFile(relativePath: "x", sha256: "s", byteCount: 1)
    }
    func storeCover(_ data: Data, bookID: UUID) async throws -> String { return "c" }
    func removeFile(relativePath: String) async throws {}
    func fileURL(relativePath: String) -> URL { return URL(fileURLWithPath: "/books/\(relativePath)") }
}

private final class ReaderInMemoryLocalBookRepository: LocalBookRepository, @unchecked Sendable {
    private var book: LocalBook
    init(book: LocalBook) { self.book = book }
    func fetchBooks(userID: String) throws -> [LocalBook] { return [self.book] }
    func fetchBook(id: UUID, userID: String) throws -> LocalBook? { return self.book.id == id ? self.book : nil }
    func fetchBook(fileSHA256: String, userID: String) throws -> LocalBook? { return nil }
    func saveBook(_ book: LocalBook) throws { self.book = book }
    func deleteBook(id: UUID, userID: String) throws {}
}

private final class ReaderInMemoryProgressRepository: BookReadingProgressRepository, @unchecked Sendable {
    private(set) var saved: [BookReadingProgress] = []
    func fetchProgress(bookID: UUID, userID: String) throws -> BookReadingProgress? { return self.saved.last }
    func saveProgress(_ progress: BookReadingProgress) throws { self.saved.append(progress) }
    func deleteProgress(bookID: UUID, userID: String) throws { self.saved.removeAll { $0.bookID == bookID } }
}

private final class ReaderInMemoryHistoryRepository: BookReadingHistoryRepository, @unchecked Sendable {
    private(set) var rows: [BookReadingHistory] = []
    func save(_ history: BookReadingHistory) throws {
        self.rows.removeAll { $0.id == history.id }
        self.rows.append(history)
    }
    func fetchHistory(userID: String) throws -> [BookReadingHistory] { return self.rows.filter { $0.userID == userID } }
    func delete(_ history: BookReadingHistory) throws { self.rows.removeAll { $0.id == history.id } }
}

private final class ReaderInMemoryBookmarkRepository: BookBookmarkRepository, @unchecked Sendable {
    private var bookmarks: [BookBookmark] = []
    func fetchBookmarks(bookID: UUID, userID: String) throws -> [BookBookmark] { return self.bookmarks.sorted { $0.createdAt > $1.createdAt } }
    func saveBookmark(_ bookmark: BookBookmark) throws { self.bookmarks.append(bookmark) }
    func deleteBookmark(id: UUID, userID: String) throws { self.bookmarks.removeAll { $0.id == id } }
    func deleteBookmarks(bookID: UUID, userID: String) throws { self.bookmarks.removeAll { $0.bookID == bookID } }
}
