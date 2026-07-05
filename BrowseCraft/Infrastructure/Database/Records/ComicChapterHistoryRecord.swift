import Foundation
import GRDB

// 中文注释：ComicChapterHistoryRecord 是 comic_chapter_history 表的一行。

/// 中文注释：该记录保存章节级阅读历史，不保存漫画列表缓存。
struct ComicChapterHistoryRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName: String = "comic_chapter_history"

    var userID: String
    var sourceID: String
    var comicItemID: String
    var comicTitle: String
    var chapterID: String?
    var chapterKey: String
    var chapterURL: String?
    var chapterTitle: String
    var visitedAt: Date
    var coverURL: String?
    var lastPageImageURL: String?
    var lastPageImageCacheKey: String?
    var lastPageIndex: Int?

    init(history: ComicChapterHistory) {
        self.userID = history.userID
        self.sourceID = history.sourceID
        self.comicItemID = history.comicItemID
        self.comicTitle = history.comicTitle
        self.chapterID = history.chapterID
        self.chapterKey = history.chapterKey
        self.chapterURL = history.chapterURL?.absoluteString
        self.chapterTitle = history.chapterTitle
        self.visitedAt = history.visitedAt
        self.coverURL = history.coverURL?.absoluteString
        self.lastPageImageURL = history.lastPageImageURL?.absoluteString
        self.lastPageImageCacheKey = history.lastPageImageCacheKey
        self.lastPageIndex = history.lastPageIndex
    }

    func domainModel() -> ComicChapterHistory {
        return ComicChapterHistory(
            userID: self.userID,
            sourceID: self.sourceID,
            comicItemID: self.comicItemID,
            comicTitle: self.comicTitle,
            chapterID: self.chapterID,
            chapterKey: self.chapterKey,
            chapterURL: self.chapterURL.flatMap(URL.init(string:)),
            chapterTitle: self.chapterTitle,
            visitedAt: self.visitedAt,
            coverURL: self.coverURL.flatMap(URL.init(string:)),
            lastPageImageURL: self.lastPageImageURL.flatMap(URL.init(string:)),
            lastPageImageCacheKey: self.lastPageImageCacheKey,
            lastPageIndex: self.lastPageIndex
        )
    }
}
