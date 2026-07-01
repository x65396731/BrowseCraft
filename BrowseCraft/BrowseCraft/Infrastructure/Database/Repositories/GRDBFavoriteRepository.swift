import Foundation
import GRDB

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

