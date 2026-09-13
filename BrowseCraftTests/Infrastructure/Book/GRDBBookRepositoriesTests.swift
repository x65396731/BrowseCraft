import Foundation
import GRDB
import Testing
@testable import BrowseCraft

// 中文注释：三张本地书表的仓储在真实迁移链上的固定输入；删书要级联掉进度与书签。

struct GRDBBookRepositoriesTests {
    private static let now: Date = Date(timeIntervalSince1970: 1_789_300_000)

    @Test func savesFetchesAndDedupesBySHA() throws {
        let database: AppDatabase = try Self.makeDatabase()
        let repository: GRDBLocalBookRepository = GRDBLocalBookRepository(database: database)
        let older: LocalBook = Self.book(sha256: "aaa", importedAt: Self.now.addingTimeInterval(-60))
        let newer: LocalBook = Self.book(sha256: "bbb", importedAt: Self.now)

        try repository.saveBook(older)
        try repository.saveBook(newer)

        #expect(try repository.fetchBooks(userID: "u1").map(\.id) == [newer.id, older.id])
        #expect(try repository.fetchBooks(userID: "someone-else").isEmpty)
        #expect(try repository.fetchBook(id: older.id, userID: "u1") == older)
        #expect(try repository.fetchBook(fileSHA256: "bbb", userID: "u1") == newer)
        #expect(try repository.fetchBook(fileSHA256: "zzz", userID: "u1") == nil)

        var reopened: LocalBook = older
        reopened.lastOpenedAt = Self.now
        reopened.title = "Renamed"
        try repository.saveBook(reopened)
        #expect(try repository.fetchBook(id: older.id, userID: "u1") == reopened)
        #expect(try repository.fetchBooks(userID: "u1").count == 2)
    }

    @Test func progressAndBookmarksAreDeletedExplicitlyAndSurviveBookDeletionOtherwise() throws {
        let database: AppDatabase = try Self.makeDatabase()
        let books: GRDBLocalBookRepository = GRDBLocalBookRepository(database: database)
        let progress: GRDBBookReadingProgressRepository = GRDBBookReadingProgressRepository(database: database)
        let bookmarks: GRDBBookBookmarkRepository = GRDBBookBookmarkRepository(database: database)
        let book: LocalBook = Self.book(sha256: "aaa", importedAt: Self.now)
        try books.saveBook(book)
        try progress.saveProgress(BookReadingProgress(bookID: book.id, userID: "u1", locatorJSON: "{\"href\":\"/c1\"}", totalProgression: 0.4, updatedAt: Self.now))
        try progress.saveProgress(BookReadingProgress(bookID: book.id, userID: "u1", locatorJSON: "{\"href\":\"/c2\"}", totalProgression: 0.6, updatedAt: Self.now))
        let first: BookBookmark = BookBookmark(id: UUID(), bookID: book.id, userID: "u1", locatorJSON: "{}", title: "One", snippet: nil, createdAt: Self.now.addingTimeInterval(-10))
        let second: BookBookmark = BookBookmark(id: UUID(), bookID: book.id, userID: "u1", locatorJSON: "{}", title: "Two", snippet: "text", createdAt: Self.now)
        try bookmarks.saveBookmark(first)
        try bookmarks.saveBookmark(second)

        #expect(try progress.fetchProgress(bookID: book.id, userID: "u1")?.locatorJSON == "{\"href\":\"/c2\"}")
        #expect(try bookmarks.fetchBookmarks(bookID: book.id, userID: "u1") == [second, first])

        try bookmarks.deleteBookmark(id: first.id, userID: "u1")
        #expect(try bookmarks.fetchBookmarks(bookID: book.id, userID: "u1") == [second])

        // 中文注释：v4 起进度与书签不外键到 local_books（站点书没有那一行）：删书不级联，由用例显式删。
        try books.deleteBook(id: book.id, userID: "u1")
        #expect(try books.fetchBook(id: book.id, userID: "u1") == nil)
        #expect(try progress.fetchProgress(bookID: book.id, userID: "u1") != nil)
        try progress.deleteProgress(bookID: book.id, userID: "u1")
        try bookmarks.deleteBookmarks(bookID: book.id, userID: "u1")
        #expect(try progress.fetchProgress(bookID: book.id, userID: "u1") == nil)
        #expect(try bookmarks.fetchBookmarks(bookID: book.id, userID: "u1").isEmpty)

        // 站点书的作品标识没有 local_books 行也能存进度
        let siteBookID: UUID = SiteBookIdentity.bookID(sourceID: "biquhua", detailURL: "https://www.biquhua.com/book/0/110/")
        try progress.saveProgress(BookReadingProgress(bookID: siteBookID, userID: "u1", locatorJSON: "{}", totalProgression: 0.1, updatedAt: Self.now))
        #expect(try progress.fetchProgress(bookID: siteBookID, userID: "u1")?.totalProgression == 0.1)
    }

    @Test func rowsWithUnknownFormatAreSkippedNotGuessed() throws {
        let database: AppDatabase = try Self.makeDatabase()
        let repository: GRDBLocalBookRepository = GRDBLocalBookRepository(database: database)
        try repository.saveBook(Self.book(sha256: "aaa", importedAt: Self.now))
        try database.queue.write { database in
            try database.execute(sql: "UPDATE local_books SET format = 'pdf'")
        }
        #expect(try repository.fetchBooks(userID: "u1").isEmpty)
    }

    private static func makeDatabase() throws -> AppDatabase {
        let path: String = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrowseCraftBookRepositoryTests-\(UUID().uuidString).sqlite")
            .path
        let database: AppDatabase = try AppDatabase(path: path)
        try GRDBAppUserRepository(database: database).saveUser(
            AppUser(id: "u1", displayName: nil, hasRemovedAds: false, pendingAdPoints: 0, createdAt: Self.now, updatedAt: Self.now)
        )
        return database
    }

    private static func book(sha256: String, importedAt: Date) -> LocalBook {
        let id: UUID = UUID()
        return LocalBook(
            id: id,
            userID: "u1",
            title: "Book \(sha256)",
            author: "Author",
            format: .epub,
            fileRelativePath: "\(id.uuidString).epub",
            coverRelativePath: nil,
            fileSHA256: sha256,
            byteCount: 12,
            importedAt: importedAt,
            lastOpenedAt: nil
        )
    }
}
