import Foundation
import GRDB

final class GRDBHistoryRepository: HistoryRepository {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

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

    func saveReadingHistory(_ history: ReadingHistory) throws {
        try self.database.queue.write { database in
            var record: ReadingHistoryRecord = ReadingHistoryRecord(history: history)
            try record.save(database)
        }
    }
}

