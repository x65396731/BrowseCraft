import Foundation

// 中文注释：VideoWatchHistoryRepository 负责视频观看历史的持久化读写。

/// 中文注释：保存语义必须是作品级覆盖，同一用户同一来源同一影片只保留最后观看记录。
protocol VideoWatchHistoryRepository: Sendable {
    func save(_ history: VideoWatchHistory) throws
    func fetchHistory(userID: String) throws -> [VideoWatchHistory]
    /// 中文注释：当前来源的全部观看历史（本就一部作品一行）；默认实现从全量里筛，GRDB 实现按 (userID, sourceID) 查。
    func fetchHistory(userID: String, sourceID: String) throws -> [VideoWatchHistory]
    func delete(_ history: VideoWatchHistory) throws
    /// 中文注释：批量删除；实现应在一个事务内完成，默认实现逐条调用 delete。
    func delete(_ histories: [VideoWatchHistory]) throws
    func fetchHistory(
        userID: String,
        sourceID: String,
        vodID: String,
        sourceIndex: Int,
        episodeIndex: Int
    ) throws -> VideoWatchHistory?
}

extension VideoWatchHistoryRepository {
    func fetchHistory(userID: String, sourceID: String) throws -> [VideoWatchHistory] {
        return try self.fetchHistory(userID: userID).filter { history in
            return history.sourceID == sourceID
        }
    }

    func delete(_ histories: [VideoWatchHistory]) throws {
        for history: VideoWatchHistory in histories {
            try self.delete(history)
        }
    }
}
