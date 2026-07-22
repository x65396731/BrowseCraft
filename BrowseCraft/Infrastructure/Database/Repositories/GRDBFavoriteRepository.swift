import Foundation
import GRDB

// 中文注释：GRDBFavoriteRepository 通过 SQLite 保存按用户聚合的收藏集合。

final class GRDBFavoriteRepository: FavoriteRepository {
    private let database: AppDatabase
    private let accountScopeProvider: any ActiveAccountScopeProviding
    private let changeNotifier: (any CloudSyncChangeNotifying)?

    init(
        database: AppDatabase,
        accountScopeProvider: any ActiveAccountScopeProviding = ActiveAccountScopeStore(),
        changeNotifier: (any CloudSyncChangeNotifying)? = nil
    ) {
        self.database = database
        self.accountScopeProvider = accountScopeProvider
        self.changeNotifier = changeNotifier
    }

    func fetchFavoriteItemIDs() throws -> Set<String> {
        let accountScope: CloudAccountScope = self.accountScopeProvider.currentScope
        return try self.database.queue.read { database in
            guard let record: FavoriteRecord = try FavoriteRecord
                .fetchOne(database, key: accountScope.rawValue) else {
                return []
            }

            return Self.decodeItemIDs(record.favoriteItemIDsJSON)
        }
    }

    func fetchFavoriteItems() throws -> [FavoriteContentItem] {
        let accountScope: CloudAccountScope = self.accountScopeProvider.currentScope
        return try self.database.queue.read { database in
            guard let record: FavoriteRecord = try FavoriteRecord.fetchOne(
                database,
                key: accountScope.rawValue
            ) else {
                return []
            }

            return Self.decodeFavoriteItems(record.favoriteItemsJSON)
        }
    }

    func setFavorite(item: FavoriteContentItem, isFavorite: Bool) throws {
        let accountScope: CloudAccountScope = self.accountScopeProvider.currentScope
        try self.database.queue.write { database in
            let userID: String = accountScope.rawValue
            let now: Date = Date()
            var record: FavoriteRecord

            try AppUserRecord.insertUser(id: userID, in: database)

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
                    updatedAt: now,
                    deletedAt: nil
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
                var itemRecord: FavoriteItemRecord = try FavoriteItemRecord(
                    userID: userID,
                    item: itemWithFavoriteDate,
                    updatedAt: now,
                    deletedAt: nil
                )
                if let existingItemRecord: FavoriteItemRecord = try FavoriteItemRecord.fetchOne(
                    database,
                    key: ["userID": userID, "itemID": item.id]
                ) {
                    itemRecord.createdAt = existingItemRecord.createdAt
                }
                try itemRecord.save(database)
            } else {
                itemIDs.remove(item.id)
                items.removeAll { $0.id == item.id }
                if var itemRecord: FavoriteItemRecord = try FavoriteItemRecord.fetchOne(
                    database,
                    key: ["userID": userID, "itemID": item.id]
                ) {
                    itemRecord.updatedAt = now
                    itemRecord.deletedAt = now
                    try itemRecord.save(database)
                } else {
                    var itemRecord: FavoriteItemRecord = try FavoriteItemRecord(
                        userID: userID,
                        item: item,
                        updatedAt: now,
                        deletedAt: now
                    )
                    try itemRecord.insert(database)
                }
            }

            record.favoriteItemIDsJSON = Self.encodeItemIDs(itemIDs)
            record.favoriteItemsJSON = Self.encodeFavoriteItems(items)
            record.updatedAt = now
            record.deletedAt = nil
            try record.save(database)
            try SyncQueueRecord.enqueue(
                accountScope: accountScope,
                entityType: .favoriteItem,
                entityID: item.id,
                operation: isFavorite ? .upsert : .delete,
                updatedAt: now,
                in: database
            )
        }
        self.changeNotifier?.notifyLocalChange()
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
