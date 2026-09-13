import Foundation

// 中文注释：DeleteLocalBookUseCase 先删库（书、进度、书签——v4 起进度与书签不再外键级联），再删文件；
// 文件删除失败不回滚库：书已经不在书架上，残留文件只占空间（UUID 不会撞）。

struct DeleteLocalBookUseCase: Sendable {
    private let repository: any LocalBookRepository
    private let progressRepository: any BookReadingProgressRepository
    private let bookmarkRepository: any BookBookmarkRepository
    private let fileStore: any BookFileStoring

    init(
        repository: any LocalBookRepository,
        progressRepository: any BookReadingProgressRepository,
        bookmarkRepository: any BookBookmarkRepository,
        fileStore: any BookFileStoring
    ) {
        self.repository = repository
        self.progressRepository = progressRepository
        self.bookmarkRepository = bookmarkRepository
        self.fileStore = fileStore
    }

    func execute(bookID: UUID, userID: String) async throws {
        guard let book: LocalBook = try self.repository.fetchBook(id: bookID, userID: userID) else {
            return
        }
        try self.bookmarkRepository.deleteBookmarks(bookID: bookID, userID: userID)
        try self.progressRepository.deleteProgress(bookID: bookID, userID: userID)
        try self.repository.deleteBook(id: bookID, userID: userID)
        try await self.fileStore.removeFile(relativePath: book.fileRelativePath)
        if let coverRelativePath: String = book.coverRelativePath {
            try await self.fileStore.removeFile(relativePath: coverRelativePath)
        }
    }
}
