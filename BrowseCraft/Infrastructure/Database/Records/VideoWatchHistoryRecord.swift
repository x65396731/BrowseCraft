import Foundation
import GRDB

// 中文注释：VideoWatchHistoryRecord 是 video_watch_history 表的一行。

/// 中文注释：该记录保存视频播放历史快照，不保存视频二进制或播放器内部缓存路径。
struct VideoWatchHistoryRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName: String = "video_watch_history"

    var userID: String
    var sourceID: String
    var vodID: String
    var videoTitle: String
    var episodeTitle: String?
    var episodeKey: String
    var sourceIndex: Int
    var episodeIndex: Int
    var detailURL: String?
    var playPageURL: String
    var candidateMediaURL: String?
    var candidateMediaKind: String
    var playbackRequestConfigJSON: String?
    var coverURL: String?
    var sourceName: String?
    var lastPlaybackTime: Double
    var duration: Double?
    var visitedAt: Date
    var updatedAt: Date
    var previousEpisodeURL: String?
    var nextEpisodeURL: String?

    init(history: VideoWatchHistory) {
        self.userID = history.userID
        self.sourceID = history.sourceID
        self.vodID = history.vodID
        self.videoTitle = history.videoTitle
        self.episodeTitle = history.episodeTitle
        self.episodeKey = history.episodeKey
        self.sourceIndex = history.sourceIndex
        self.episodeIndex = history.episodeIndex
        self.detailURL = history.detailURL?.absoluteString
        self.playPageURL = history.playPageURL.absoluteString
        self.candidateMediaURL = history.candidateMediaURL?.absoluteString
        self.candidateMediaKind = history.candidateMediaKind.rawValue
        self.playbackRequestConfigJSON = Self.encodePlaybackRequestConfig(history.playbackRequestConfig)
        self.coverURL = history.coverURL?.absoluteString
        self.sourceName = history.sourceName
        self.lastPlaybackTime = history.lastPlaybackTime
        self.duration = history.duration
        self.visitedAt = history.visitedAt
        self.updatedAt = history.updatedAt
        self.previousEpisodeURL = history.previousEpisodeURL?.absoluteString
        self.nextEpisodeURL = history.nextEpisodeURL?.absoluteString
    }

    func domainModel() -> VideoWatchHistory {
        return VideoWatchHistory(
            userID: self.userID,
            sourceID: self.sourceID,
            vodID: self.vodID,
            videoTitle: self.videoTitle,
            episodeTitle: self.episodeTitle,
            episodeKey: self.episodeKey,
            sourceIndex: self.sourceIndex,
            episodeIndex: self.episodeIndex,
            detailURL: self.detailURL.flatMap(URL.init(string:)),
            playPageURL: URL(string: self.playPageURL) ?? URL(fileURLWithPath: "/"),
            candidateMediaURL: self.candidateMediaURL.flatMap(URL.init(string:)),
            candidateMediaKind: SourceVideoMediaKind(rawValue: self.candidateMediaKind) ?? .unknown,
            playbackRequestConfig: Self.decodePlaybackRequestConfig(self.playbackRequestConfigJSON),
            coverURL: self.coverURL.flatMap(URL.init(string:)),
            sourceName: self.sourceName,
            lastPlaybackTime: self.lastPlaybackTime,
            duration: self.duration,
            visitedAt: self.visitedAt,
            updatedAt: self.updatedAt,
            previousEpisodeURL: self.previousEpisodeURL.flatMap(URL.init(string:)),
            nextEpisodeURL: self.nextEpisodeURL.flatMap(URL.init(string:))
        )
    }

    private static func encodePlaybackRequestConfig(_ config: SourcePlaybackRequestConfig?) -> String? {
        guard let config: SourcePlaybackRequestConfig = config,
              let data: Data = try? JSONEncoder().encode(config) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    private static func decodePlaybackRequestConfig(_ json: String?) -> SourcePlaybackRequestConfig? {
        guard let json: String = json,
              let data: Data = json.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode(SourcePlaybackRequestConfig.self, from: data)
    }
}
