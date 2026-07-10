import Foundation
import GRDB

// 中文注释：FavoriteItemRecord 是 favorite_items 表的一行，按收藏 item 粒度保存同步明细。
struct FavoriteItemRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName: String = "favorite_items"

    var userID: String
    var itemID: String
    var sourceID: String
    var kind: String
    var title: String
    var detailURL: String
    var coverURL: String?
    var latestText: String?
    var itemJSON: String
    var sourceSnapshotJSON: String?
    var favoritedAt: Date?
    var updatedAt: Date
    var deletedAt: Date?
    var createdAt: Date

    init(
        userID: String,
        item: FavoriteContentItem,
        updatedAt: Date,
        deletedAt: Date?
    ) throws {
        var itemForStorage: FavoriteContentItem = item
        if itemForStorage.favoritedAt == nil, deletedAt == nil {
            itemForStorage.favoritedAt = updatedAt
        }

        self.userID = userID
        self.itemID = itemForStorage.id
        self.sourceID = itemForStorage.sourceID
        self.kind = itemForStorage.kind.rawValue
        self.title = itemForStorage.title
        self.detailURL = itemForStorage.detailURL
        self.coverURL = itemForStorage.coverURL
        self.latestText = itemForStorage.latestText
        self.itemJSON = try Self.encodeItem(itemForStorage)
        self.sourceSnapshotJSON = try Self.encodeSourceSnapshot(itemForStorage.sourceSnapshot)
        self.favoritedAt = itemForStorage.favoritedAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.createdAt = updatedAt
    }

    func favoriteItem() -> FavoriteContentItem? {
        guard let item: FavoriteContentItem = Self.decodeItem(self.itemJSON) else {
            return nil
        }

        return item
    }

    var lastChangedAt: Date {
        return max(self.updatedAt, self.deletedAt ?? .distantPast)
    }

    private static func encodeItem(_ item: FavoriteContentItem) throws -> String {
        let data: Data = try JSONEncoder().encode(item)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func decodeItem(_ json: String) -> FavoriteContentItem? {
        guard let data: Data = json.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode(FavoriteContentItem.self, from: data)
    }

    private static func encodeSourceSnapshot(_ snapshot: FavoriteSourceSnapshot?) throws -> String? {
        guard let snapshot: FavoriteSourceSnapshot = snapshot else {
            return nil
        }

        let data: Data = try JSONEncoder().encode(snapshot)
        return String(data: data, encoding: .utf8)
    }
}
