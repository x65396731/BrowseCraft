import Foundation

// 中文注释：VideoWatchHistory 保存用户看过的视频剧集和上次播放位置。

/// 中文注释：一条记录对应同一影片、同一播放源、同一集；History 展示依赖这里的快照字段，不重新请求网络。
struct VideoWatchHistory: Identifiable, Hashable {
    var id: String {
        return [
            self.userID,
            self.sourceID,
            self.vodID,
            String(self.sourceIndex),
            String(self.episodeIndex)
        ].joined(separator: "::")
    }

    var userID: String
    var sourceID: String
    var vodID: String
    var videoTitle: String
    var episodeTitle: String?
    var episodeKey: String
    var sourceIndex: Int
    var episodeIndex: Int
    var detailURL: URL?
    var playPageURL: URL
    var candidateMediaURL: URL?
    var candidateMediaKind: SourceVideoMediaKind
    var playbackRequestConfig: SourcePlaybackRequestConfig?
    var coverURL: URL?
    var sourceName: String?
    /// 中文注释：lastPlaybackTime 只用于恢复播放位置，不参与历史记录身份判断。
    var lastPlaybackTime: TimeInterval
    var duration: TimeInterval?
    var visitedAt: Date
    var updatedAt: Date
    var previousEpisodeURL: URL?
    var nextEpisodeURL: URL?
}
