import Foundation

// 中文注释：读书线的同步 Repository 调用隔离到专用 actor（与 Library / History / Favorites 同一模式），
// ViewModel 只在 MainActor 应用结果，主线程不再直接做 SQLite I/O。

/// 中文注释：书架——列本地书。
actor BookShelfPersistenceCoordinator {
    private let listUseCase: ListLocalBooksUseCase

    init(listUseCase: ListLocalBooksUseCase) {
        self.listUseCase = listUseCase
    }

    func shelfItems(userID: String) throws -> [LocalBookShelfItem] {
        return try self.listUseCase.execute(userID: userID)
    }
}

/// 中文注释：阅读器——续读位置与书签。进度落库仍由 ViewModel 的节流器同步执行（离开阅读器时 flush 必须立即完成）。
actor BookReaderPersistenceCoordinator {
    private let loadProgressUseCase: LoadBookReadingProgressUseCase
    private let addBookmarkUseCase: AddBookBookmarkUseCase
    private let listBookmarksUseCase: ListBookBookmarksUseCase
    private let removeBookmarkUseCase: RemoveBookBookmarkUseCase

    init(
        loadProgressUseCase: LoadBookReadingProgressUseCase,
        addBookmarkUseCase: AddBookBookmarkUseCase,
        listBookmarksUseCase: ListBookBookmarksUseCase,
        removeBookmarkUseCase: RemoveBookBookmarkUseCase
    ) {
        self.loadProgressUseCase = loadProgressUseCase
        self.addBookmarkUseCase = addBookmarkUseCase
        self.listBookmarksUseCase = listBookmarksUseCase
        self.removeBookmarkUseCase = removeBookmarkUseCase
    }

    func readingProgress(bookID: UUID, userID: String) throws -> BookReadingProgress? {
        return try self.loadProgressUseCase.execute(bookID: bookID, userID: userID)
    }

    func bookmarks(bookID: UUID, userID: String) throws -> [BookBookmark] {
        return try self.listBookmarksUseCase.execute(bookID: bookID, userID: userID)
    }

    @discardableResult
    func addBookmark(bookID: UUID, userID: String, locatorJSON: String, title: String?, snippet: String?) throws -> BookBookmark {
        return try self.addBookmarkUseCase.execute(
            bookID: bookID,
            userID: userID,
            locatorJSON: locatorJSON,
            title: title,
            snippet: snippet
        )
    }

    func removeBookmark(bookmarkID: UUID, userID: String) throws {
        try self.removeBookmarkUseCase.execute(bookmarkID: bookmarkID, userID: userID)
    }
}
