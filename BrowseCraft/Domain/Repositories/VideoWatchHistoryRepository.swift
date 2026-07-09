import Foundation

// 中文注释：VideoWatchHistoryRepository 负责视频观看历史的持久化读写。

/// 中文注释：保存语义必须是作品级覆盖，同一用户同一来源同一影片只保留最后观看记录。
protocol VideoWatchHistoryRepository {
    func save(_ history: VideoWatchHistory) throws
    func fetchHistory(userID: String) throws -> [VideoWatchHistory]
    func delete(_ history: VideoWatchHistory) throws
    func fetchHistory(
        userID: String,
        sourceID: String,
        vodID: String,
        sourceIndex: Int,
        episodeIndex: Int
    ) throws -> VideoWatchHistory?
}
