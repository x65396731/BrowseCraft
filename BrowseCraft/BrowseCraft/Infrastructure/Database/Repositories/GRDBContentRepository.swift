import Foundation
import GRDB

// 中文注释：GRDBContentRepository.swift 属于数据库仓储实现层，用于说明本文件承载的核心职责。

/// 中文注释：GRDBContentRepository 是 final class，负责本模块中的对应职责。
final class GRDBContentRepository: ContentRepository {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    /// 中文注释：fetchItems 方法封装当前类型的一段业务或界面行为。
    func fetchItems() throws -> [ContentItem] {
        return try self.fetchItems(sourceId: nil)
    }

    /// 中文注释：fetchItems 方法封装当前类型的一段业务或界面行为。
    func fetchItems(sourceId: String?) throws -> [ContentItem] {
        return try self.database.queue.read { database in
            let records: [ContentItemRecord]

            if let sourceId: String = sourceId {
                records = try ContentItemRecord
                    .filter(Column("sourceId") == sourceId)
                    .order(Column("updatedAt").desc)
                    .fetchAll(database)
            } else {
                records = try ContentItemRecord
                    .order(Column("updatedAt").desc)
                    .fetchAll(database)
            }

            return records.map { record in
                return record.domainModel()
            }
        }
    }

    /// 中文注释：saveItems 方法封装当前类型的一段业务或界面行为。
    func saveItems(_ items: [ContentItem]) throws {
        try self.database.queue.write { database in
            for item: ContentItem in items {
                var record: ContentItemRecord = ContentItemRecord(item: item)
                try record.save(database)
            }
        }
    }
}

