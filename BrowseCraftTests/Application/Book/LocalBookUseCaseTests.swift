import Foundation
import Testing
@testable import BrowseCraft

// 中文注释：本地书用例的固定输入——端口与仓储全用内存替身，不碰文件系统与 Readium。

struct LocalBookUseCaseTests {
    private static let now: Date = Date(timeIntervalSince1970: 1_789_300_000)
    private static let bookID: UUID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    @Test func importCopiesOpensAndSavesBook() async throws {
        let store: InMemoryBookFileStore = InMemoryBookFileStore()
        let repository: InMemoryLocalBookRepository = InMemoryLocalBookRepository()
        let opener: StubBookPublicationOpener = StubBookPublicationOpener(
            metadata: BookPublicationMetadata(title: "  Pride and Prejudice ", author: "Jane Austen", coverImageData: Data([1, 2, 3]), isRestricted: false)
        )
        let useCase: ImportLocalBookUseCase = Self.makeImportUseCase(
            inspection: .supported(.epub, fileExtension: "epub"), store: store, opener: opener, repository: repository
        )

        let book: LocalBook = try await useCase.execute(sourceURL: URL(fileURLWithPath: "/tmp/pp.epub"), userID: "u1")

        #expect(book.id == Self.bookID)
        #expect(book.title == "Pride and Prejudice")
        #expect(book.author == "Jane Austen")
        #expect(book.format == .epub)
        #expect(book.fileRelativePath == "11111111-1111-1111-1111-111111111111.epub")
        #expect(book.coverRelativePath == "11111111-1111-1111-1111-111111111111.cover")
        #expect(book.fileSHA256 == "sha-/tmp/pp.epub")
        #expect(book.importedAt == Self.now)
        #expect(repository.books == [book])
        #expect(store.storedRelativePaths == [book.fileRelativePath, book.coverRelativePath!])
        #expect(opener.openedFormats == [.epub])
    }

    @Test func importFallsBackToFileNameWhenPublicationHasNoTitle() async throws {
        let repository: InMemoryLocalBookRepository = InMemoryLocalBookRepository()
        let useCase: ImportLocalBookUseCase = Self.makeImportUseCase(
            inspection: .supported(.audiobook, fileExtension: "m4b"),
            store: InMemoryBookFileStore(),
            opener: StubBookPublicationOpener(metadata: BookPublicationMetadata(title: nil, author: nil, coverImageData: nil, isRestricted: false)),
            repository: repository
        )

        let book: LocalBook = try await useCase.execute(sourceURL: URL(fileURLWithPath: "/tmp/Tom Sawyer.m4b"), userID: "u1")

        #expect(book.title == "Tom Sawyer")
        #expect(book.format == .audiobook)
        #expect(book.coverRelativePath == nil)
    }

    @Test func importRejectsUnsupportedFilesBeforeCopying() async throws {
        let store: InMemoryBookFileStore = InMemoryBookFileStore()
        let useCase: ImportLocalBookUseCase = Self.makeImportUseCase(
            inspection: .unsupported, store: store, opener: StubBookPublicationOpener(metadata: nil), repository: InMemoryLocalBookRepository()
        )

        await #expect(throws: LocalBookImportError.unsupportedFormat) {
            _ = try await useCase.execute(sourceURL: URL(fileURLWithPath: "/tmp/x.pdf"), userID: "u1")
        }
        #expect(store.storedRelativePaths.isEmpty)
    }

    @Test func importRemovesCopiedFileWhenPublicationIsProtected() async throws {
        let store: InMemoryBookFileStore = InMemoryBookFileStore()
        let repository: InMemoryLocalBookRepository = InMemoryLocalBookRepository()
        let useCase: ImportLocalBookUseCase = Self.makeImportUseCase(
            inspection: .supported(.epub, fileExtension: "epub"),
            store: store,
            opener: StubBookPublicationOpener(metadata: BookPublicationMetadata(title: "Locked", author: nil, coverImageData: nil, isRestricted: true)),
            repository: repository
        )

        await #expect(throws: LocalBookImportError.protectedPublication) {
            _ = try await useCase.execute(sourceURL: URL(fileURLWithPath: "/tmp/locked.epub"), userID: "u1")
        }
        #expect(store.storedRelativePaths.isEmpty)
        #expect(store.removedRelativePaths == ["11111111-1111-1111-1111-111111111111.epub"])
        #expect(repository.books.isEmpty)
    }

    @Test func importRemovesCopiedFileWhenOpeningFails() async throws {
        let store: InMemoryBookFileStore = InMemoryBookFileStore()
        let useCase: ImportLocalBookUseCase = Self.makeImportUseCase(
            inspection: .supported(.epub, fileExtension: "epub"),
            store: store,
            opener: StubBookPublicationOpener(metadata: nil, error: .parsingFailed(reason: "bad-zip")),
            repository: InMemoryLocalBookRepository()
        )

        await #expect(throws: LocalBookImportError.openFailed(reason: "bad-zip")) {
            _ = try await useCase.execute(sourceURL: URL(fileURLWithPath: "/tmp/bad.epub"), userID: "u1")
        }
        #expect(store.storedRelativePaths.isEmpty)
    }

    @Test func importingTheSameFileAgainReturnsExistingBookAndDropsTheCopy() async throws {
        let store: InMemoryBookFileStore = InMemoryBookFileStore()
        let repository: InMemoryLocalBookRepository = InMemoryLocalBookRepository()
        let existing: LocalBook = Self.book(id: UUID(), sha256: "sha-/tmp/pp.epub")
        try repository.saveBook(existing)
        let opener: StubBookPublicationOpener = StubBookPublicationOpener(metadata: nil)
        let useCase: ImportLocalBookUseCase = Self.makeImportUseCase(
            inspection: .supported(.epub, fileExtension: "epub"), store: store, opener: opener, repository: repository
        )

        let book: LocalBook = try await useCase.execute(sourceURL: URL(fileURLWithPath: "/tmp/pp.epub"), userID: "u1")

        #expect(book == existing)
        #expect(repository.books == [existing])
        #expect(store.storedRelativePaths.isEmpty)
        #expect(opener.openedFormats.isEmpty)
    }

    @Test func openReturnsHandleAndLastPositionAndStampsLastOpenedAt() async throws {
        let repository: InMemoryLocalBookRepository = InMemoryLocalBookRepository()
        let progressRepository: InMemoryBookReadingProgressRepository = InMemoryBookReadingProgressRepository()
        let book: LocalBook = Self.book(id: Self.bookID, sha256: "s")
        try repository.saveBook(book)
        try progressRepository.saveProgress(
            BookReadingProgress(bookID: Self.bookID, userID: "u1", locatorJSON: "{\"href\":\"/c1\"}", totalProgression: 0.25, updatedAt: Self.now)
        )
        let useCase: OpenLocalBookUseCase = OpenLocalBookUseCase(
            repository: repository,
            progressRepository: progressRepository,
            fileStore: InMemoryBookFileStore(),
            opener: StubBookPublicationOpener(metadata: BookPublicationMetadata(title: "T", author: nil, coverImageData: nil, isRestricted: false)),
            now: { Self.now }
        )

        let opened: OpenedLocalBook = try await useCase.execute(bookID: Self.bookID, userID: "u1")

        #expect(opened.initialLocatorJSON == "{\"href\":\"/c1\"}")
        #expect(opened.book.lastOpenedAt == Self.now)
        #expect(repository.books.first?.lastOpenedAt == Self.now)
        #expect(opened.publication.metadata.title == "T")
    }

    @Test func openMissingBookFails() async throws {
        let useCase: OpenLocalBookUseCase = OpenLocalBookUseCase(
            repository: InMemoryLocalBookRepository(),
            progressRepository: InMemoryBookReadingProgressRepository(),
            fileStore: InMemoryBookFileStore(),
            opener: StubBookPublicationOpener(metadata: nil)
        )
        await #expect(throws: OpenLocalBookError.bookNotFound) {
            _ = try await useCase.execute(bookID: UUID(), userID: "u1")
        }
    }

    @Test func saveProgressClampsTotalProgression() throws {
        let progressRepository: InMemoryBookReadingProgressRepository = InMemoryBookReadingProgressRepository()
        let useCase: SaveBookReadingProgressUseCase = SaveBookReadingProgressUseCase(progressRepository: progressRepository, now: { Self.now })

        try useCase.execute(bookID: Self.bookID, userID: "u1", locatorJSON: "{}", totalProgression: 1.7)

        #expect(progressRepository.progress[Self.bookID]?.totalProgression == 1)
        #expect(progressRepository.progress[Self.bookID]?.updatedAt == Self.now)
    }

    @Test func listPairsBooksWithProgress() throws {
        let repository: InMemoryLocalBookRepository = InMemoryLocalBookRepository()
        let progressRepository: InMemoryBookReadingProgressRepository = InMemoryBookReadingProgressRepository()
        let read: LocalBook = Self.book(id: Self.bookID, sha256: "a")
        let unread: LocalBook = Self.book(id: UUID(), sha256: "b")
        try repository.saveBook(read)
        try repository.saveBook(unread)
        try progressRepository.saveProgress(BookReadingProgress(bookID: read.id, userID: "u1", locatorJSON: "{}", totalProgression: 0.5, updatedAt: Self.now))

        let items: [LocalBookShelfItem] = try ListLocalBooksUseCase(repository: repository, progressRepository: progressRepository).execute(userID: "u1")

        #expect(items.map(\.book.id) == [read.id, unread.id])
        #expect(items.map(\.totalProgression) == [0.5, nil])
    }

    @Test func deleteRemovesRowThenFiles() async throws {
        let repository: InMemoryLocalBookRepository = InMemoryLocalBookRepository()
        let store: InMemoryBookFileStore = InMemoryBookFileStore()
        var book: LocalBook = Self.book(id: Self.bookID, sha256: "a")
        book.coverRelativePath = "cover.jpg"
        try repository.saveBook(book)

        let progressRepository: InMemoryBookReadingProgressRepository = InMemoryBookReadingProgressRepository()
        let bookmarkRepository: InMemoryBookBookmarkRepository = InMemoryBookBookmarkRepository()
        try progressRepository.saveProgress(BookReadingProgress(bookID: Self.bookID, userID: "u1", locatorJSON: "{}", totalProgression: 0.2, updatedAt: Self.now))
        try bookmarkRepository.saveBookmark(BookBookmark(id: UUID(), bookID: Self.bookID, userID: "u1", locatorJSON: "{}", title: nil, snippet: nil, createdAt: Self.now))

        try await DeleteLocalBookUseCase(
            repository: repository,
            progressRepository: progressRepository,
            bookmarkRepository: bookmarkRepository,
            fileStore: store
        ).execute(bookID: Self.bookID, userID: "u1")

        #expect(repository.books.isEmpty)
        #expect(progressRepository.progress[Self.bookID] == nil, "v4 起进度不再级联，用例显式删")
        #expect(try bookmarkRepository.fetchBookmarks(bookID: Self.bookID, userID: "u1").isEmpty)
        #expect(store.removedRelativePaths == [book.fileRelativePath, "cover.jpg"])
    }

    @Test func bookmarksRoundTrip() throws {
        let repository: InMemoryBookBookmarkRepository = InMemoryBookBookmarkRepository()
        let added: BookBookmark = try AddBookBookmarkUseCase(repository: repository, now: { Self.now }, makeID: { Self.bookID })
            .execute(bookID: Self.bookID, userID: "u1", locatorJSON: "{\"href\":\"/c2\"}", title: "Chapter 2", snippet: "It is a truth")

        #expect(try ListBookBookmarksUseCase(repository: repository).execute(bookID: Self.bookID, userID: "u1") == [added])
        try RemoveBookBookmarkUseCase(repository: repository).execute(bookmarkID: added.id, userID: "u1")
        #expect(try ListBookBookmarksUseCase(repository: repository).execute(bookID: Self.bookID, userID: "u1").isEmpty)
    }

    // MARK: - Helpers

    private static func makeImportUseCase(
        inspection: LocalBookFileInspection,
        store: InMemoryBookFileStore,
        opener: StubBookPublicationOpener,
        repository: InMemoryLocalBookRepository
    ) -> ImportLocalBookUseCase {
        return ImportLocalBookUseCase(
            inspector: StubBookFileInspector(inspection: inspection),
            fileStore: store,
            opener: opener,
            repository: repository,
            now: { Self.now },
            makeID: { Self.bookID }
        )
    }

    private static func book(id: UUID, sha256: String) -> LocalBook {
        return LocalBook(
            id: id,
            userID: "u1",
            title: "Book \(sha256)",
            author: nil,
            format: .epub,
            fileRelativePath: "\(id.uuidString).epub",
            coverRelativePath: nil,
            fileSHA256: sha256,
            byteCount: 10,
            importedAt: Self.now,
            lastOpenedAt: nil
        )
    }
}

// MARK: - Doubles

private struct StubBookFileInspector: BookFileInspecting {
    let inspection: LocalBookFileInspection

    func inspect(fileURL: URL) async throws -> LocalBookFileInspection {
        return self.inspection
    }
}

private final class InMemoryBookFileStore: BookFileStoring, @unchecked Sendable {
    private(set) var storedRelativePaths: [String] = []
    private(set) var removedRelativePaths: [String] = []

    func storeBookFile(from sourceURL: URL, bookID: UUID, fileExtension: String) async throws -> StoredBookFile {
        let relativePath: String = "\(bookID.uuidString).\(fileExtension)"
        self.storedRelativePaths.append(relativePath)
        return StoredBookFile(relativePath: relativePath, sha256: "sha-\(sourceURL.path)", byteCount: 42)
    }

    func storeCover(_ data: Data, bookID: UUID) async throws -> String {
        let relativePath: String = "\(bookID.uuidString).cover"
        self.storedRelativePaths.append(relativePath)
        return relativePath
    }

    func removeFile(relativePath: String) async throws {
        self.storedRelativePaths.removeAll { $0 == relativePath }
        self.removedRelativePaths.append(relativePath)
    }

    func fileURL(relativePath: String) -> URL {
        return URL(fileURLWithPath: "/books/\(relativePath)")
    }
}

private final class StubBookPublicationHandle: BookPublicationHandle, @unchecked Sendable {
    let metadata: BookPublicationMetadata

    init(metadata: BookPublicationMetadata) {
        self.metadata = metadata
    }
}

private final class StubBookPublicationOpener: BookPublicationOpening, @unchecked Sendable {
    private let metadata: BookPublicationMetadata?
    private let error: BookPublicationOpenError?
    private(set) var openedFormats: [LocalBookFormat] = []

    init(metadata: BookPublicationMetadata?, error: BookPublicationOpenError? = nil) {
        self.metadata = metadata
        self.error = error
    }

    func openPublication(fileURL: URL, format: LocalBookFormat) async throws -> BookPublicationHandle {
        self.openedFormats.append(format)
        if let error: BookPublicationOpenError = self.error {
            throw error
        }
        guard let metadata: BookPublicationMetadata = self.metadata else {
            throw BookPublicationOpenError.parsingFailed(reason: "no-stub-metadata")
        }
        return StubBookPublicationHandle(metadata: metadata)
    }
}

private final class InMemoryLocalBookRepository: LocalBookRepository, @unchecked Sendable {
    private(set) var books: [LocalBook] = []

    func fetchBooks(userID: String) throws -> [LocalBook] {
        return self.books.filter { $0.userID == userID }
    }

    func fetchBook(id: UUID, userID: String) throws -> LocalBook? {
        return self.books.first { $0.id == id && $0.userID == userID }
    }

    func fetchBook(fileSHA256: String, userID: String) throws -> LocalBook? {
        return self.books.first { $0.fileSHA256 == fileSHA256 && $0.userID == userID }
    }

    func saveBook(_ book: LocalBook) throws {
        self.books.removeAll { $0.id == book.id }
        self.books.append(book)
    }

    func deleteBook(id: UUID, userID: String) throws {
        self.books.removeAll { $0.id == id && $0.userID == userID }
    }
}

private final class InMemoryBookReadingProgressRepository: BookReadingProgressRepository, @unchecked Sendable {
    private(set) var progress: [UUID: BookReadingProgress] = [:]

    func fetchProgress(bookID: UUID, userID: String) throws -> BookReadingProgress? {
        return self.progress[bookID]
    }

    func saveProgress(_ progress: BookReadingProgress) throws {
        self.progress[progress.bookID] = progress
    }

    func deleteProgress(bookID: UUID, userID: String) throws {
        self.progress[bookID] = nil
    }
}

private final class InMemoryBookBookmarkRepository: BookBookmarkRepository, @unchecked Sendable {
    private var bookmarks: [BookBookmark] = []

    func fetchBookmarks(bookID: UUID, userID: String) throws -> [BookBookmark] {
        return self.bookmarks.filter { $0.bookID == bookID && $0.userID == userID }.sorted { $0.createdAt > $1.createdAt }
    }

    func saveBookmark(_ bookmark: BookBookmark) throws {
        self.bookmarks.append(bookmark)
    }

    func deleteBookmark(id: UUID, userID: String) throws {
        self.bookmarks.removeAll { $0.id == id && $0.userID == userID }
    }

    func deleteBookmarks(bookID: UUID, userID: String) throws {
        self.bookmarks.removeAll { $0.bookID == bookID && $0.userID == userID }
    }
}
