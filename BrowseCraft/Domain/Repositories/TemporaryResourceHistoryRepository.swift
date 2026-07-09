import Foundation

// 中文注释：TemporaryResourceHistoryRepository 管理不绑定 Source 的临时资源历史。
protocol TemporaryResourceHistoryRepository {
    func save(_ history: TemporaryResourceHistory) throws
    func fetchHistory(userID: String) throws -> [TemporaryResourceHistory]
    func delete(_ history: TemporaryResourceHistory) throws
}
