import Foundation
import GRDB

// 中文注释：GRDBSourceRepository.swift 属于数据库仓储实现层，用于说明本文件承载的核心职责。

/// 中文注释：GRDBSourceRepository 是 final class，负责本模块中的对应职责。
final class GRDBSourceRepository: SourceRepository {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    /// 中文注释：fetchSources 方法封装当前类型的一段业务或界面行为。
    func fetchSources() throws -> [Source] {
        return try self.database.queue.read { database in
            let records: [SourceRecord] = try SourceRecord
                .order(Column("updatedAt").desc)
                .fetchAll(database)

            return try records.map { record in
                return try record.domainModel()
            }
        }
    }

    /// 中文注释：saveSource 方法封装当前类型的一段业务或界面行为。
    func saveSource(_ source: Source) throws {
        try self.database.queue.write { database in
            var record: SourceRecord = try SourceRecord(source: source)
            try record.save(database)
        }
    }

    /// 中文注释：deleteSource 方法封装当前类型的一段业务或界面行为。
    func deleteSource(id: String) throws {
        try self.database.queue.write { database in
            _ = try SourceRecord.deleteOne(database, key: id)
        }
    }
}
