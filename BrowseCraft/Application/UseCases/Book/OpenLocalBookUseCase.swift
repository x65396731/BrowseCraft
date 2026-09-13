import Foundation

// 中文注释：OpenLocalBookUseCase 打开一本本地书：给 Features 出版物句柄与上次的续读位置，并记下 lastOpenedAt。

struct OpenedLocalBook: Sendable {
    let book: LocalBook
    let publication: any BookPublicationHandle
    /// 中文注释：上次续读位置的 Locator JSON；第一次打开为 nil。
    let initialLocatorJSON: String?
}

enum OpenLocalBookError: Error, Equatable, Sendable {
    case bookNotFound
}

struct OpenLocalBookUseCase: Sendable {
    private let repository: any LocalBookRepository
    private let progressRepository: any BookReadingProgressRepository
    private let fileStore: any BookFileStoring
    private let opener: any BookPublicationOpening
    private let now: @Sendable () -> Date

    init(
        repository: any LocalBookRepository,
        progressRepository: any BookReadingProgressRepository,
        fileStore: any BookFileStoring,
        opener: any BookPublicationOpening,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.repository = repository
        self.progressRepository = progressRepository
        self.fileStore = fileStore
        self.opener = opener
        self.now = now
    }

    func execute(bookID: UUID, userID: String) async throws -> OpenedLocalBook {
        guard var book: LocalBook = try self.repository.fetchBook(id: bookID, userID: userID) else {
            throw OpenLocalBookError.bookNotFound
        }
        let handle: any BookPublicationHandle = try await self.opener.openPublication(
            fileURL: self.fileStore.fileURL(relativePath: book.fileRelativePath),
            format: book.format
        )
        let progress: BookReadingProgress? = try self.progressRepository.fetchProgress(bookID: bookID, userID: userID)
        book.lastOpenedAt = self.now()
        try self.repository.saveBook(book)
        return OpenedLocalBook(book: book, publication: handle, initialLocatorJSON: progress?.locatorJSON)
    }
}
