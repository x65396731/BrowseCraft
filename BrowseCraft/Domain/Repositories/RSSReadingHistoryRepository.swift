import Foundation

// 中文注释：RSSReadingHistoryRepository 负责 RSS 详情访问历史的持久化读写。

/// 中文注释：保存语义必须是 upsert，同一用户同一 RSS item 再次访问时更新旧快照。
protocol RSSReadingHistoryRepository {
    func save(_ history: RSSReadingHistory) throws
    func fetchHistory(userID: String) throws -> [RSSReadingHistory]
    func delete(_ history: RSSReadingHistory) throws
}
