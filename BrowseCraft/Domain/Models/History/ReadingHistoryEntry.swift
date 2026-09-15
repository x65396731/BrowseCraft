import Foundation

// 中文注释：ReadingHistoryEntry 是 History 页面展示漫画、视频、站点书与临时资源历史的聚合行模型。

/// 中文注释：该模型只聚合 DB 历史记录，不反查 Library 当前快照，也不触发网络请求。
struct ReadingHistoryEntry: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable {
        case comic
        case video
        case book
        case temporary
    }

    var id: String
    var kind: Kind
    var userID: String
    var sourceID: String
    var title: String
    var subtitle: String?
    var visitedAt: Date
    var comicHistory: ComicChapterHistory?
    var videoHistory: VideoWatchHistory?
    var bookHistory: BookReadingHistory?
    var temporaryHistory: TemporaryResourceHistory?

    init(comicHistory: ComicChapterHistory) {
        self.id = "comic::\(comicHistory.id)"
        self.kind = .comic
        self.userID = comicHistory.userID
        self.sourceID = comicHistory.sourceID
        self.title = comicHistory.comicTitle
        self.subtitle = comicHistory.chapterTitle
        self.visitedAt = comicHistory.visitedAt
        self.comicHistory = comicHistory
        self.videoHistory = nil
        self.bookHistory = nil
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
        self.comicHistory = nil
        self.videoHistory = videoHistory
        self.bookHistory = nil
        self.temporaryHistory = nil
    }

    init(bookHistory: BookReadingHistory) {
        self.id = "book::\(bookHistory.id)"
        self.kind = .book
        self.userID = bookHistory.userID
        self.sourceID = bookHistory.sourceID
        self.title = bookHistory.bookTitle
        self.subtitle = bookHistory.chapterTitle
        self.visitedAt = bookHistory.visitedAt
        self.comicHistory = nil
        self.videoHistory = nil
        self.bookHistory = bookHistory
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
        self.comicHistory = nil
        self.videoHistory = nil
        self.bookHistory = nil
        self.temporaryHistory = temporaryHistory
    }
}
