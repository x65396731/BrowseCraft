import Foundation

// 中文注释：VideoWatchHistory 保存用户看过的视频作品和上次播放位置。

/// 中文注释：一条记录对应同一影片；History 展示依赖这里的快照字段，不重新请求网络。
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
    var playbackStatus: SourceVideoPlaybackStatus
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
    var sourceSnapshot: SourceSnapshot? = nil

    var workHistoryKey: String {
        let trimmedVodID: String = self.vodID.trimmingCharacters(in: .whitespacesAndNewlines)
        let workID: String
        if trimmedVodID.isEmpty == false {
            workID = "vod::\(trimmedVodID)"
        } else if let detailURL: URL = self.detailURL {
            workID = "detail::\(detailURL.absoluteString)"
        } else {
            workID = "title::\(self.videoTitle)"
        }

        return [
            self.userID,
            self.sourceID,
            workID
        ].joined(separator: "::")
    }

    func playbackReference(defaultSourceName: String) -> SourceVideoPlaybackReference {
        return SourceVideoPlaybackReference(
            vodID: self.vodID,
            sourceIndex: self.sourceIndex,
            episodeIndex: self.episodeIndex,
            episodeKey: self.episodeKey,
            episodeTitle: self.episodeTitle,
            playPageURL: self.playPageURL,
            candidateMediaURL: self.candidateMediaURL,
            candidateMediaKind: self.candidateMediaKind,
            playbackRequestConfig: self.playbackRequestConfig,
            nextEpisodeURL: self.nextEpisodeURL,
            previousEpisodeURL: self.previousEpisodeURL,
            sourceName: self.sourceName ?? defaultSourceName,
            status: self.playbackStatus
        )
    }

    func fallbackSource() -> Source? {
        return self.sourceSnapshot?.source()
    }
}
