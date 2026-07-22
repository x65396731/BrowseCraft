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

    func fetchFavoriteItemIDs(sourceID: String?) throws -> Set<String> {
        let accountScope: CloudAccountScope = self.accountScopeProvider.currentScope
        return try self.database.queue.read { database in
            var request: QueryInterfaceRequest<FavoriteItemRecord> = FavoriteItemRecord
                .filter(FavoriteItemRecord.Columns.userID == accountScope.rawValue)
                .filter(FavoriteItemRecord.Columns.deletedAt == nil)
            if let sourceID: String {
                request = request.filter(FavoriteItemRecord.Columns.sourceID == sourceID)
            }
            return Set(try request.fetchAll(database).map(\.itemID))
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
            try AppUserRecord.insertUser(id: userID, in: database)
            let recordKey: [String: String] = [
                "userID": userID,
                "sourceID": item.sourceID,
                "itemID": item.id
            ]
            if isFavorite {
                var itemWithFavoriteDate: FavoriteContentItem = item
                itemWithFavoriteDate.favoritedAt = now
                var itemRecord: FavoriteItemRecord = try FavoriteItemRecord(
                    userID: userID,
                    item: itemWithFavoriteDate,
                    updatedAt: now,
                    deletedAt: nil
                )
                if let existingItemRecord: FavoriteItemRecord = try FavoriteItemRecord.fetchOne(
                    database,
                    key: recordKey
                ) {
                    itemRecord.createdAt = existingItemRecord.createdAt
                }
                try itemRecord.save(database)
            } else {
                if var itemRecord: FavoriteItemRecord = try FavoriteItemRecord.fetchOne(
                    database,
                    key: recordKey
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
            try FavoriteAggregateBuilder.rebuild(userID: userID, in: database)
            try SyncQueueRecord.enqueue(
                accountScope: accountScope,
                entityType: .favoriteItem,
                entityID: item.identity.syncEntityID,
                operation: isFavorite ? .upsert : .delete,
                updatedAt: now,
                in: database
            )
        }
        self.changeNotifier?.notifyLocalChange()
    }

    private static func decodeFavoriteItems(_ json: String) -> [FavoriteContentItem] {
        guard let data: Data = json.data(using: .utf8),
              let items: [FavoriteContentItem] = try? JSONDecoder().decode([FavoriteContentItem].self, from: data) else {
            return []
        }

        return items
    }
}
