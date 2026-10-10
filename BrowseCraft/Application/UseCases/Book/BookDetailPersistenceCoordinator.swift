import Foundation

/// 站点书详情页一次读回的续读位置：进度表那一条 + 读书历史那一条。
struct BookReadingPositionSnapshot: Sendable {
    let progress: BookReadingProgress?
    let history: BookReadingHistory?
}

/// 中文注释：站点书详情的进度与历史读取离开主线程（2026-10-10 复审 B-3）；历史按 (userID, sourceID, bookItemID) 查一条，
/// 不再读全表再在内存里找。ViewModel 在 init 里自建，装配根不用改。
actor BookDetailPersistenceCoordinator {
    private let loadProgressUseCase: LoadBookReadingProgressUseCase
    private let readingHistoryRepository: (any BookReadingHistoryRepository)?

    init(
        loadProgressUseCase: LoadBookReadingProgressUseCase,
        readingHistoryRepository: (any BookReadingHistoryRepository)?
    ) {
        self.loadProgressUseCase = loadProgressUseCase
        self.readingHistoryRepository = readingHistoryRepository
    }

    func loadReadingPosition(
        bookID: UUID,
        userID: String,
        sourceID: String,
        bookItemID: String
    ) throws -> BookReadingPositionSnapshot {
        let progress: BookReadingProgress? = try self.loadProgressUseCase.execute(bookID: bookID, userID: userID)
        let history: BookReadingHistory? = try self.readingHistoryRepository?.fetchHistory(
            userID: userID,
            sourceID: sourceID,
            bookItemID: bookItemID
        )
        return BookReadingPositionSnapshot(progress: progress, history: history)
    }
}
