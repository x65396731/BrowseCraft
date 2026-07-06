import Foundation

// 中文注释：VideoWatchHistoryRepository 负责视频观看历史的持久化读写。

/// 中文注释：保存语义必须是 upsert，同一用户同一影片同一播放源同一集再次观看时更新旧进度。
protocol VideoWatchHistoryRepository {
    func save(_ history: VideoWatchHistory) throws
    func fetchHistory(userID: String) throws -> [VideoWatchHistory]
    func fetchHistory(
        userID: String,
        sourceID: String,
        vodID: String,
        sourceIndex: Int,
        episodeIndex: Int
    ) throws -> VideoWatchHistory?
}
