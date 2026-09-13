import Foundation
import Testing
@testable import BrowseCraft

// 中文注释：书架视图模型：导入成功进列表、失败汇总成一条提示、删除后列表更新。用例与端口全用替身。

@MainActor
struct BookShelfViewModelTests {
    @Test func importAddsBookAndReloads() async throws {
        let repository: ShelfInMemoryLocalBookRepository = ShelfInMemoryLocalBookRepository()
        let viewModel: BookShelfViewModel = Self.makeViewModel(
            repository: repository,
            inspection: .supported(.epub, fileExtension: "epub"),
            metadata: BookPublicationMetadata(title: "Imported", author: nil, coverImageData: nil, isRestricted: false)
        )

        await viewModel.importBooks(from: [URL(fileURLWithPath: "/tmp/a.epub")])

        #expect(viewModel.items.map(\.book.title) == ["Imported"])
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.isImporting == false)
    }

    @Test func importFailuresAreCollectedPerFile() async throws {
        let viewModel: BookShelfViewModel = Self.makeViewModel(
            repository: ShelfInMemoryLocalBookRepository(),
            inspection: .unsupported,
            metadata: nil
        )

        await viewModel.importBooks(from: [URL(fileURLWithPath: "/tmp/a.pdf"), URL(fileURLWithPath: "/tmp/b.txt")])

        #expect(viewModel.items.isEmpty)
        let message: String = try #require(viewModel.errorMessage)
        #expect(message.contains("a.pdf"))
        #expect(message.contains("b.txt"))
        #expect(message.split(separator: "\n").count == 2)
    }

    @Test func deleteRemovesBookFromShelf() async throws {
        let repository: ShelfInMemoryLocalBookRepository = ShelfInMemoryLocalBookRepository()
        let book: LocalBook = LocalBook(
            id: UUID(), userID: "u1", title: "T", author: nil, format: .epub, fileRelativePath: "x.epub",
            coverRelativePath: nil, fileSHA256: "s", byteCount: 1, importedAt: Date(), lastOpenedAt: nil
        )
        try repository.saveBook(book)
        let viewModel: BookShelfViewModel = Self.makeViewModel(repository: repository, inspection: .unsupported, metadata: nil)
        viewModel.load()
        #expect(viewModel.items.count == 1)

        await viewModel.delete(book)

        #expect(viewModel.items.isEmpty)
    }

    private static func makeViewModel(
        repository: ShelfInMemoryLocalBookRepository,
        inspection: LocalBookFileInspection,
        metadata: BookPublicationMetadata?
    ) -> BookShelfViewModel {
        let store: ShelfInMemoryBookFileStore = ShelfInMemoryBookFileStore()
        let progress: ShelfInMemoryProgressRepository = ShelfInMemoryProgressRepository()
        return BookShelfViewModel(
            listUseCase: ListLocalBooksUseCase(repository: repository, progressRepository: progress),
            importUseCase: ImportLocalBookUseCase(
                inspector: ShelfStubInspector(inspection: inspection),
                fileStore: store,
                opener: ShelfStubOpener(metadata: metadata),
                repository: repository
            ),
            deleteUseCase: DeleteLocalBookUseCase(repository: repository, fileStore: store),
            fileStore: store,
            userID: "u1"
        )
    }
}

private struct ShelfStubInspector: BookFileInspecting {
    let inspection: LocalBookFileInspection
    func inspect(fileURL: URL) async throws -> LocalBookFileInspection { return self.inspection }
}

private final class ShelfStubHandle: BookPublicationHandle, @unchecked Sendable {
    let metadata: BookPublicationMetadata
    init(metadata: BookPublicationMetadata) { self.metadata = metadata }
}

private struct ShelfStubOpener: BookPublicationOpening {
    let metadata: BookPublicationMetadata?
    func openPublication(fileURL: URL, format: LocalBookFormat) async throws -> BookPublicationHandle {
        guard let metadata: BookPublicationMetadata = self.metadata else {
            throw BookPublicationOpenError.parsingFailed(reason: "stub")
        }
        return ShelfStubHandle(metadata: metadata)
    }
}

private final class ShelfInMemoryBookFileStore: BookFileStoring, @unchecked Sendable {
    func storeBookFile(from sourceURL: URL, bookID: UUID, fileExtension: String) async throws -> StoredBookFile {
        return StoredBookFile(relativePath: "\(bookID.uuidString).\(fileExtension)", sha256: "sha-\(sourceURL.path)", byteCount: 1)
    }
    func storeCover(_ data: Data, bookID: UUID) async throws -> String { return "\(bookID.uuidString).cover" }
    func removeFile(relativePath: String) async throws {}
    func fileURL(relativePath: String) -> URL { return URL(fileURLWithPath: "/books/\(relativePath)") }
}

private final class ShelfInMemoryLocalBookRepository: LocalBookRepository, @unchecked Sendable {
    private var books: [LocalBook] = []
    func fetchBooks(userID: String) throws -> [LocalBook] { return self.books.filter { $0.userID == userID } }
    func fetchBook(id: UUID, userID: String) throws -> LocalBook? { return self.books.first { $0.id == id } }
    func fetchBook(fileSHA256: String, userID: String) throws -> LocalBook? { return self.books.first { $0.fileSHA256 == fileSHA256 } }
    func saveBook(_ book: LocalBook) throws {
        self.books.removeAll { $0.id == book.id }
        self.books.append(book)
    }
    func deleteBook(id: UUID, userID: String) throws { self.books.removeAll { $0.id == id } }
}

private final class ShelfInMemoryProgressRepository: BookReadingProgressRepository, @unchecked Sendable {
    func fetchProgress(bookID: UUID, userID: String) throws -> BookReadingProgress? { return nil }
    func saveProgress(_ progress: BookReadingProgress) throws {}
}
