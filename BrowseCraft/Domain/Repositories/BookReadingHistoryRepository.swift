import Foundation

// 中文注释：BookReadingHistoryRepository 负责站点书阅读历史的持久化读写，一本书一条。

/// 中文注释：save 按 userID/sourceID/detailURL upsert；删除只删历史行，不动续读位置与书签。
protocol BookReadingHistoryRepository: Sendable {
    func save(_ history: BookReadingHistory) throws
    func fetchHistory(userID: String) throws -> [BookReadingHistory]
    func delete(_ history: BookReadingHistory) throws
    /// 中文注释：批量删除；实现应在一个事务内完成，默认实现逐条调用 delete。
    func delete(_ histories: [BookReadingHistory]) throws
}

extension BookReadingHistoryRepository {
    func delete(_ histories: [BookReadingHistory]) throws {
        for history: BookReadingHistory in histories {
            try self.delete(history)
        }
    }
}
