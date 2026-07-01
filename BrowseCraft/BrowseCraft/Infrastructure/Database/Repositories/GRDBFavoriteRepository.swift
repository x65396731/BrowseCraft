import Foundation
import GRDB

// 中文注释：GRDBFavoriteRepository.swift 属于数据库仓储实现层，用于说明本文件承载的核心职责。

/// 中文注释：GRDBFavoriteRepository 是 final class，负责本模块中的对应职责。
final class GRDBFavoriteRepository: FavoriteRepository {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    /// 中文注释：fetchFavoriteItemIDs 方法封装当前类型的一段业务或界面行为。
    func fetchFavoriteItemIDs() throws -> Set<String> {
        return try self.database.queue.read { database in
            let records: [FavoriteRecord] = try FavoriteRecord.fetchAll(database)
            let ids: [String] = records.map { record in
                return record.itemId
            }

            return Set(ids)
        }
    }

    /// 中文注释：setFavorite 方法封装当前类型的一段业务或界面行为。
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

