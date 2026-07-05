import Foundation
import GRDB

// 中文注释：RSSReadingHistoryRecord 是 rss_reading_history 表的一行。

/// 中文注释：该记录保存 RSS 详情快照，不保存 RSS feed 列表缓存。
struct RSSReadingHistoryRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName: String = "rss_reading_history"

    var userID: String
    var sourceID: String
    var itemID: String
    var dataType: String
    var title: String
    var dataContent: String
    var dataTime: Date
    var visitedAt: Date
    var detailURL: String?
    var sourceName: String?
    var originFeedURL: String?

    init(history: RSSReadingHistory) {
        self.userID = history.userID
        self.sourceID = history.sourceID
        self.itemID = history.itemID
        self.dataType = history.dataType.rawValue
        self.title = history.title
        self.dataContent = history.dataContent
        self.dataTime = history.dataTime
        self.visitedAt = history.visitedAt
        self.detailURL = history.detailURL?.absoluteString
        self.sourceName = history.sourceName
        self.originFeedURL = history.originFeedURL?.absoluteString
    }

    func domainModel() -> RSSReadingHistory {
        return RSSReadingHistory(
            userID: self.userID,
            sourceID: self.sourceID,
            itemID: self.itemID,
            dataType: ContentType(rawValue: self.dataType) ?? .article,
            title: self.title,
            dataContent: self.dataContent,
            dataTime: self.dataTime,
            visitedAt: self.visitedAt,
            detailURL: self.detailURL.flatMap(URL.init(string:)),
            sourceName: self.sourceName,
            originFeedURL: self.originFeedURL.flatMap(URL.init(string:))
        )
    }
}
