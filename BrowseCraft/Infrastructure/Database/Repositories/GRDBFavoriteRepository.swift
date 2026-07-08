import Foundation
import GRDB

// 中文注释：GRDBFavoriteRepository 通过 SQLite 保存按用户聚合的收藏集合。

final class GRDBFavoriteRepository: FavoriteRepository {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func fetchFavoriteItemIDs() throws -> Set<String> {
        return try self.database.queue.read { database in
            guard let record: FavoriteRecord = try FavoriteRecord
                .fetchOne(database, key: AppUser.localDefaultID) else {
                return []
            }

            return Self.decodeItemIDs(record.favoriteItemIDsJSON)
        }
    }

    func fetchFavoriteItems() throws -> [FavoriteContentItem] {
        return try self.database.queue.read { database in
            guard let record: FavoriteRecord = try FavoriteRecord.fetchOne(database, key: AppUser.localDefaultID) else {
                return []
            }

            return Self.decodeFavoriteItems(record.favoriteItemsJSON)
        }
    }

    func setFavorite(item: FavoriteContentItem, isFavorite: Bool) throws {
        try self.database.queue.write { database in
            let userID: String = AppUser.localDefaultID
            let now: Date = Date()
            var record: FavoriteRecord

            if let existing: FavoriteRecord = try FavoriteRecord.fetchOne(database, key: userID) {
                record = existing
            } else {
                record = FavoriteRecord(
                    userID: userID,
                    favoriteItemIDsJSON: "[]",
                    favoriteItemsJSON: "[]",
                    rssFavoritesJSON: nil,
                    comicFavoritesJSON: nil,
                    videoFavoritesJSON: nil,
                    createdAt: now,
                    updatedAt: now
                )
            }

            var itemIDs: Set<String> = Self.decodeItemIDs(record.favoriteItemIDsJSON)
            var items: [FavoriteContentItem] = Self.decodeFavoriteItems(record.favoriteItemsJSON)
            if isFavorite {
                var itemWithFavoriteDate: FavoriteContentItem = item
                itemWithFavoriteDate.favoritedAt = now
                itemIDs.insert(item.id)
                items.removeAll { $0.id == item.id }
                items.append(itemWithFavoriteDate)
            } else {
                itemIDs.remove(item.id)
                items.removeAll { $0.id == item.id }
            }

            record.favoriteItemIDsJSON = Self.encodeItemIDs(itemIDs)
            record.favoriteItemsJSON = Self.encodeFavoriteItems(items)
            record.updatedAt = now
            try record.save(database)
        }
    }

    private static func decodeItemIDs(_ json: String) -> Set<String> {
        guard let data: Data = json.data(using: .utf8),
              let itemIDs: [String] = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }

        return Set(itemIDs)
    }

    private static func encodeItemIDs(_ itemIDs: Set<String>) -> String {
        let sortedIDs: [String] = itemIDs.sorted()
        guard let data: Data = try? JSONEncoder().encode(sortedIDs),
              let json: String = String(data: data, encoding: .utf8) else {
            return "[]"
        }

        return json
    }

    private static func decodeFavoriteItems(_ json: String) -> [FavoriteContentItem] {
        guard let data: Data = json.data(using: .utf8),
              let items: [FavoriteContentItem] = try? JSONDecoder().decode([FavoriteContentItem].self, from: data) else {
            return []
        }

        return items
    }

    private static func encodeFavoriteItems(_ items: [FavoriteContentItem]) -> String {
        let sortedItems: [FavoriteContentItem] = items.sorted { lhs, rhs in
            let lhsDate: Date = lhs.favoritedAt ?? lhs.updatedAt ?? .distantPast
            let rhsDate: Date = rhs.favoritedAt ?? rhs.updatedAt ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }

            return lhs.id < rhs.id
        }

        guard let data: Data = try? JSONEncoder().encode(sortedItems),
              let json: String = String(data: data, encoding: .utf8) else {
            return "[]"
        }

        return json
    }
}
