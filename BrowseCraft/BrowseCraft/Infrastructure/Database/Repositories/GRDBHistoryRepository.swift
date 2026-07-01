import Foundation
import GRDB

// 中文注释：GRDBHistoryRepository.swift 属于数据库仓储实现层，用于说明本文件承载的核心职责。

/// 中文注释：GRDBHistoryRepository 是 final class，负责本模块中的对应职责。
final class GRDBHistoryRepository: HistoryRepository {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    /// 中文注释：fetchReadingHistory 方法封装当前类型的一段业务或界面行为。
    func fetchReadingHistory() throws -> [ReadingHistory] {
        return try self.database.queue.read { database in
            let records: [ReadingHistoryRecord] = try ReadingHistoryRecord
                .order(Column("updatedAt").desc)
                .fetchAll(database)

            return records.map { record in
                return record.domainModel()
            }
        }
    }

    /// 中文注释：saveReadingHistory 方法封装当前类型的一段业务或界面行为。
    func saveReadingHistory(_ history: ReadingHistory) throws {
        try self.database.queue.write { database in
            var record: ReadingHistoryRecord = ReadingHistoryRecord(history: history)
            try record.save(database)
        }
    }
}

