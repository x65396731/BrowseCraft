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
    var lastReaderPageURL: String?
    var lastPageImageURL: String?
    var lastPageImageCacheKey: String?
    var lastPageIndex: Int?
    var previousChapterURL: String?
    var nextChapterURL: String?
    var sourceSnapshotJSON: String?

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
        self.lastReaderPageURL = history.lastReaderPageURL?.absoluteString
        self.lastPageImageURL = history.lastPageImageURL?.absoluteString
        self.lastPageImageCacheKey = history.lastPageImageCacheKey
        self.lastPageIndex = history.lastPageIndex
        self.previousChapterURL = history.previousChapterURL?.absoluteString
        self.nextChapterURL = history.nextChapterURL?.absoluteString
        self.sourceSnapshotJSON = Self.encodeSourceSnapshot(history.sourceSnapshot)
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
            lastReaderPageURL: self.lastReaderPageURL.flatMap(URL.init(string:)),
            lastPageImageURL: self.lastPageImageURL.flatMap(URL.init(string:)),
            lastPageImageCacheKey: self.lastPageImageCacheKey,
            lastPageIndex: self.lastPageIndex,
            previousChapterURL: self.previousChapterURL.flatMap(URL.init(string:)),
            nextChapterURL: self.nextChapterURL.flatMap(URL.init(string:)),
            sourceSnapshot: Self.decodeSourceSnapshot(self.sourceSnapshotJSON)
        )
    }

    private static func encodeSourceSnapshot(_ snapshot: SourceSnapshot?) -> String? {
        guard let snapshot: SourceSnapshot = snapshot,
              let data: Data = try? JSONEncoder().encode(snapshot) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    private static func decodeSourceSnapshot(_ json: String?) -> SourceSnapshot? {
        guard let json: String = json,
              let data: Data = json.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode(SourceSnapshot.self, from: data)
    }
}
