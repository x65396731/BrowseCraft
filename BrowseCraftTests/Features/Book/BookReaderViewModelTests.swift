import Foundation
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

        viewModel.addBookmarkAtCurrentLocation()

        #expect(viewModel.bookmarks.count == 1)
        #expect(viewModel.bookmarks.first?.title == "Chapter 1")
        let restored: Locator = try #require(BookReaderViewModel.locator(fromJSON: viewModel.bookmarks[0].locatorJSON))
        #expect(restored.locations.totalProgression == 0.3)
        viewModel.removeBookmark(viewModel.bookmarks[0])
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
            book: book,
            userID: "u1",
            openUseCase: OpenLocalBookUseCase(repository: books, progressRepository: progress, fileStore: store, opener: ReadiumBookPublicationOpener()),
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

    // MARK: - Helpers

    private static func makeViewModel(progress: ReaderInMemoryProgressRepository, throttleNanoseconds: UInt64) -> BookReaderViewModel {
        let book: LocalBook = LocalBook(
            id: UUID(), userID: "u1", title: "T", author: nil, format: .epub, fileRelativePath: "x.epub",
            coverRelativePath: nil, fileSHA256: "s", byteCount: 1, importedAt: Date(), lastOpenedAt: nil
        )
        let bookmarks: ReaderInMemoryBookmarkRepository = ReaderInMemoryBookmarkRepository()
        return BookReaderViewModel(
            book: book,
            userID: "u1",
            openUseCase: OpenLocalBookUseCase(
                repository: ReaderInMemoryLocalBookRepository(book: book),
                progressRepository: progress,
                fileStore: ReaderStubFileStore(),
                opener: ReaderFailingOpener()
            ),
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
}

private final class ReaderInMemoryBookmarkRepository: BookBookmarkRepository, @unchecked Sendable {
    private var bookmarks: [BookBookmark] = []
    func fetchBookmarks(bookID: UUID, userID: String) throws -> [BookBookmark] { return self.bookmarks.sorted { $0.createdAt > $1.createdAt } }
    func saveBookmark(_ bookmark: BookBookmark) throws { self.bookmarks.append(bookmark) }
    func deleteBookmark(id: UUID, userID: String) throws { self.bookmarks.removeAll { $0.id == id } }
}
