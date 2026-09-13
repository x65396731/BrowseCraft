import Foundation

// 中文注释：书签三个用例放一个文件：加、列、删。位置是 Locator JSON，Application 不解释。

struct AddBookBookmarkUseCase: Sendable {
    private let repository: any BookBookmarkRepository
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID

    init(
        repository: any BookBookmarkRepository,
        now: @escaping @Sendable () -> Date = { Date() },
        makeID: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.repository = repository
        self.now = now
        self.makeID = makeID
    }

    @discardableResult
    func execute(bookID: UUID, userID: String, locatorJSON: String, title: String?, snippet: String?) throws -> BookBookmark {
        let bookmark: BookBookmark = BookBookmark(
            id: self.makeID(),
            bookID: bookID,
            userID: userID,
            locatorJSON: locatorJSON,
            title: title,
            snippet: snippet,
            createdAt: self.now()
        )
        try self.repository.saveBookmark(bookmark)
        return bookmark
    }
}

struct ListBookBookmarksUseCase: Sendable {
    private let repository: any BookBookmarkRepository

    init(repository: any BookBookmarkRepository) {
        self.repository = repository
    }

    func execute(bookID: UUID, userID: String) throws -> [BookBookmark] {
        return try self.repository.fetchBookmarks(bookID: bookID, userID: userID)
    }
}

struct RemoveBookBookmarkUseCase: Sendable {
    private let repository: any BookBookmarkRepository

    init(repository: any BookBookmarkRepository) {
        self.repository = repository
    }

    func execute(bookmarkID: UUID, userID: String) throws {
        try self.repository.deleteBookmark(id: bookmarkID, userID: userID)
    }
}
