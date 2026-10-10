import Foundation

// 中文注释：BookReadingHistoryRepository 负责站点书阅读历史的持久化读写，一本书一条。

/// 中文注释：save 按 userID/sourceID/detailURL upsert；删除只删历史行，不动续读位置与书签。
protocol BookReadingHistoryRepository: Sendable {
    func save(_ history: BookReadingHistory) throws
    func fetchHistory(userID: String) throws -> [BookReadingHistory]
    /// 中文注释：当前来源读过的全部书（一本一条）；默认实现从全量里筛，GRDB 实现按 (userID, sourceID) 查。
    func fetchHistory(userID: String, sourceID: String) throws -> [BookReadingHistory]
    /// 中文注释：某一本书的那一条（站点书详情的续读章）；默认实现从全量里找，GRDB 实现按列查。
    func fetchHistory(userID: String, sourceID: String, bookItemID: String) throws -> BookReadingHistory?
    func delete(_ history: BookReadingHistory) throws
    /// 中文注释：批量删除；实现应在一个事务内完成，默认实现逐条调用 delete。
    func delete(_ histories: [BookReadingHistory]) throws
}

extension BookReadingHistoryRepository {
    func fetchHistory(userID: String, sourceID: String) throws -> [BookReadingHistory] {
        return try self.fetchHistory(userID: userID).filter { history in
            return history.sourceID == sourceID
        }
    }

    func fetchHistory(userID: String, sourceID: String, bookItemID: String) throws -> BookReadingHistory? {
        return try self.fetchHistory(userID: userID).first { history in
            return history.sourceID == sourceID && history.bookItemID == bookItemID
        }
    }

    func delete(_ histories: [BookReadingHistory]) throws {
        for history: BookReadingHistory in histories {
            try self.delete(history)
        }
    }
}
