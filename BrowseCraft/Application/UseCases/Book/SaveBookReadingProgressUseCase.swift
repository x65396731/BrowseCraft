import Foundation

// 中文注释：SaveBookReadingProgressUseCase 只负责写；节流（阅读中每秒最多一次）由 Features 做。

struct SaveBookReadingProgressUseCase: Sendable {
    private let progressRepository: any BookReadingProgressRepository
    private let now: @Sendable () -> Date

    init(progressRepository: any BookReadingProgressRepository, now: @escaping @Sendable () -> Date = { Date() }) {
        self.progressRepository = progressRepository
        self.now = now
    }

    func execute(bookID: UUID, userID: String, locatorJSON: String, totalProgression: Double?) throws {
        let clamped: Double? = totalProgression.map { min(max($0, 0), 1) }
        try self.progressRepository.saveProgress(
            BookReadingProgress(
                bookID: bookID,
                userID: userID,
                locatorJSON: locatorJSON,
                totalProgression: clamped,
                updatedAt: self.now()
            )
        )
    }
}
