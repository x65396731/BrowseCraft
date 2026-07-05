import Foundation
import GRDB

// 中文注释：GRDBSourceRepository 通过 SQLite 保存和读取 Source。

/// 中文注释：这是 App 正式 source 仓储实现，用于支撑启动状态恢复和 source 配置持久化。
final class GRDBSourceRepository: SourceRepository {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

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

    func saveSource(_ source: Source) throws {
        try self.database.queue.write { database in
            var record: SourceRecord = try SourceRecord(source: source)
            try record.save(database)
        }
    }

    func deleteSource(id: String) throws {
        try self.database.queue.write { database in
            _ = try SourceRecord.deleteOne(database, key: id)
        }
    }
}
