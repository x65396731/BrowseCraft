import Foundation

// 中文注释：TemporaryResourceHistoryRepository 管理不绑定 Source 的临时资源历史。
protocol TemporaryResourceHistoryRepository: Sendable {
    func save(_ history: TemporaryResourceHistory) throws
    func fetchHistory(userID: String) throws -> [TemporaryResourceHistory]
    func delete(_ history: TemporaryResourceHistory) throws
    /// 中文注释：批量删除；实现应在一个事务内完成，默认实现逐条调用 delete。
    func delete(_ histories: [TemporaryResourceHistory]) throws
}

extension TemporaryResourceHistoryRepository {
    func delete(_ histories: [TemporaryResourceHistory]) throws {
        for history: TemporaryResourceHistory in histories {
            try self.delete(history)
        }
    }
}
