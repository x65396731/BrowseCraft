import Foundation

// 中文注释：LoadBookReadingProgressUseCase 只读一本书（本地或站点）的续读位置；站点书没有 OpenLocalBookUseCase 那条路。

struct LoadBookReadingProgressUseCase: Sendable {
    private let progressRepository: any BookReadingProgressRepository

    init(progressRepository: any BookReadingProgressRepository) {
        self.progressRepository = progressRepository
    }

    func execute(bookID: UUID, userID: String) throws -> BookReadingProgress? {
        return try self.progressRepository.fetchProgress(bookID: bookID, userID: userID)
    }
}
