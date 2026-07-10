import Foundation
import GRDB

// 中文注释：FavoriteAggregateBuilder 从 favorite_items 明细重建 favorites 聚合 JSON，供现有 UI 继续快速读取。
enum FavoriteAggregateBuilder {
    static func rebuild(userID: String, in database: Database) throws {
        let records: [FavoriteItemRecord] = try FavoriteItemRecord
            .filter(FavoriteItemRecord.Columns.userID == userID)
            .filter(FavoriteItemRecord.Columns.deletedAt == nil)
            .order(FavoriteItemRecord.Columns.favoritedAt.desc)
            .fetchAll(database)

        let items: [FavoriteContentItem] = records.compactMap { record in
            return record.favoriteItem()
        }
        let itemIDs: [String] = items.map(\.id).sorted()
        let sortedItems: [FavoriteContentItem] = items.sorted { lhs, rhs in
            let lhsDate: Date = lhs.favoritedAt ?? lhs.updatedAt ?? .distantPast
            let rhsDate: Date = rhs.favoritedAt ?? rhs.updatedAt ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }

            return lhs.id < rhs.id
        }

        let now: Date = Date()
        let existing: FavoriteRecord? = try FavoriteRecord.fetchOne(database, key: userID)
        var record: FavoriteRecord = existing ?? FavoriteRecord(
            userID: userID,
            favoriteItemIDsJSON: "[]",
            favoriteItemsJSON: "[]",
            rssFavoritesJSON: nil,
            comicFavoritesJSON: nil,
            videoFavoritesJSON: nil,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )

        record.favoriteItemIDsJSON = try Self.encode(itemIDs)
        record.favoriteItemsJSON = try Self.encode(sortedItems)
        record.updatedAt = now
        record.deletedAt = nil
        try record.save(database)
    }

    private static func encode<Value: Encodable>(_ value: Value) throws -> String {
        let data: Data = try JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
