import Foundation

// 中文注释：ReadingHistoryEntry 是 History 页面未来展示 RSS/漫画历史的聚合行模型。

/// 中文注释：该模型只聚合 DB 历史记录，不反查 Library 当前快照，也不触发网络请求。
struct ReadingHistoryEntry: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case rss
        case comic
        case video
        case temporary
    }

    var id: String
    var kind: Kind
    var userID: String
    var sourceID: String
    var title: String
    var subtitle: String?
    var visitedAt: Date
    var rssHistory: RSSReadingHistory?
    var comicHistory: ComicChapterHistory?
    var videoHistory: VideoWatchHistory?
    var temporaryHistory: TemporaryResourceHistory?

    init(rssHistory: RSSReadingHistory) {
        self.id = "rss::\(rssHistory.id)"
        self.kind = .rss
        self.userID = rssHistory.userID
        self.sourceID = rssHistory.sourceID
        self.title = rssHistory.title
        self.subtitle = rssHistory.sourceName
        self.visitedAt = rssHistory.visitedAt
        self.rssHistory = rssHistory
        self.comicHistory = nil
        self.videoHistory = nil
        self.temporaryHistory = nil
    }

    init(comicHistory: ComicChapterHistory) {
        self.id = "comic::\(comicHistory.id)"
        self.kind = .comic
        self.userID = comicHistory.userID
        self.sourceID = comicHistory.sourceID
        self.title = comicHistory.comicTitle
        self.subtitle = comicHistory.chapterTitle
        self.visitedAt = comicHistory.visitedAt
        self.rssHistory = nil
        self.comicHistory = comicHistory
        self.videoHistory = nil
        self.temporaryHistory = nil
    }

    init(videoHistory: VideoWatchHistory) {
        self.id = "video::\(videoHistory.id)"
        self.kind = .video
        self.userID = videoHistory.userID
        self.sourceID = videoHistory.sourceID
        self.title = videoHistory.videoTitle
        self.subtitle = videoHistory.episodeTitle
        self.visitedAt = videoHistory.updatedAt
        self.rssHistory = nil
        self.comicHistory = nil
        self.videoHistory = videoHistory
        self.temporaryHistory = nil
    }

    init(temporaryHistory: TemporaryResourceHistory) {
        self.id = "temporary::\(temporaryHistory.id)"
        self.kind = .temporary
        self.userID = temporaryHistory.userID
        self.sourceID = "temporary"
        self.title = temporaryHistory.title
        self.subtitle = temporaryHistory.kind == .video ? "Temporary Video" : "Temporary Comic"
        self.visitedAt = temporaryHistory.visitedAt
        self.rssHistory = nil
        self.comicHistory = nil
        self.videoHistory = nil
        self.temporaryHistory = temporaryHistory
    }
}
