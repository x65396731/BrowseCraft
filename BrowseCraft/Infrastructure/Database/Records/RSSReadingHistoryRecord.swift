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
    var sourceSnapshotJSON: String?

    init(history: RSSReadingHistory) {
        self.userID = history.userID
        self.sourceID = history.sourceID
        self.itemID = Self.storageItemID(for: history)
        self.dataType = history.dataType.rawValue
        self.title = history.title
        self.dataContent = history.dataContent
        self.dataTime = history.dataTime
        self.visitedAt = history.visitedAt
        self.detailURL = history.detailURL?.absoluteString
        self.sourceName = history.sourceName
        self.originFeedURL = history.originFeedURL?.absoluteString
        self.sourceSnapshotJSON = Self.encodeSourceSnapshot(history.sourceSnapshot)
    }

    func domainModel() -> RSSReadingHistory {
        return RSSReadingHistory(
            userID: self.userID,
            sourceID: self.sourceID,
            itemID: self.itemID,
            dataType: SourceContentKind(rawValue: self.dataType) ?? .article,
            title: self.title,
            dataContent: self.dataContent,
            dataTime: self.dataTime,
            visitedAt: self.visitedAt,
            detailURL: self.detailURL.flatMap(URL.init(string:)),
            sourceName: self.sourceName,
            originFeedURL: self.originFeedURL.flatMap(URL.init(string:)),
            sourceSnapshot: Self.decodeSourceSnapshot(self.sourceSnapshotJSON)
        )
    }

    private static func storageItemID(for history: RSSReadingHistory) -> String {
        let trimmedItemID: String = history.itemID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedItemID.isEmpty == false {
            return trimmedItemID
        }

        if let detailURL: URL = history.detailURL {
            return "detail::\(detailURL.absoluteString)"
        }

        return "title::\(history.title)"
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
