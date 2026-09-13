import Foundation

// 中文注释：DeleteLocalBookUseCase 先删库（进度与书签外键级联），再删文件；文件删除失败不回滚库——
// 书已经不在书架上，残留文件由下次导入同名 bookID 不可能撞上（UUID），留着只占空间。

struct DeleteLocalBookUseCase: Sendable {
    private let repository: any LocalBookRepository
    private let fileStore: any BookFileStoring

    init(repository: any LocalBookRepository, fileStore: any BookFileStoring) {
        self.repository = repository
        self.fileStore = fileStore
    }

    func execute(bookID: UUID, userID: String) async throws {
        guard let book: LocalBook = try self.repository.fetchBook(id: bookID, userID: userID) else {
            return
        }
        try self.repository.deleteBook(id: bookID, userID: userID)
        try await self.fileStore.removeFile(relativePath: book.fileRelativePath)
        if let coverRelativePath: String = book.coverRelativePath {
            try await self.fileStore.removeFile(relativePath: coverRelativePath)
        }
    }
}
