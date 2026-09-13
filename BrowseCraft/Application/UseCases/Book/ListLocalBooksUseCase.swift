import Foundation

// 中文注释：ListLocalBooksUseCase 给书架用：书 + 各自的续读进度（只取 totalProgression 画进度条）。

struct LocalBookShelfItem: Hashable, Sendable {
    let book: LocalBook
    let totalProgression: Double?
}

struct ListLocalBooksUseCase: Sendable {
    private let repository: any LocalBookRepository
    private let progressRepository: any BookReadingProgressRepository

    init(repository: any LocalBookRepository, progressRepository: any BookReadingProgressRepository) {
        self.repository = repository
        self.progressRepository = progressRepository
    }

    func execute(userID: String) throws -> [LocalBookShelfItem] {
        return try self.repository.fetchBooks(userID: userID).map { book in
            let progress: BookReadingProgress? = try self.progressRepository.fetchProgress(bookID: book.id, userID: userID)
            return LocalBookShelfItem(book: book, totalProgression: progress?.totalProgression)
        }
    }
}
