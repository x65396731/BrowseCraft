import Foundation
import GRDB

// 中文注释：GRDBFavoriteRepository 通过 SQLite 保存收藏状态。

/// 中文注释：收藏仍是内容级轻量状态，不参与 P4.10 的阅读历史表设计。
final class GRDBFavoriteRepository: FavoriteRepository {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func fetchFavoriteItemIDs() throws -> Set<String> {
        return try self.database.queue.read { database in
            let records: [FavoriteRecord] = try FavoriteRecord.fetchAll(database)
            let ids: [String] = records.map { record in
                return record.itemId
            }

            return Set(ids)
        }
    }

    func setFavorite(itemId: String, isFavorite: Bool) throws {
        try self.database.queue.write { database in
            if isFavorite {
                var record: FavoriteRecord = FavoriteRecord(itemId: itemId, createdAt: Date())
                try record.save(database)
            } else {
                _ = try FavoriteRecord.deleteOne(database, key: itemId)
            }
        }
    }
}
