import Foundation
import GRDB

// 中文注释：GRDBBookReadingProgressRepository 每本书每个用户一条续读位置，save 按 (bookID, userID) upsert。

final class GRDBBookReadingProgressRepository: BookReadingProgressRepository {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func fetchProgress(bookID: UUID, userID: String) throws -> BookReadingProgress? {
        return try self.database.queue.read { database in
            return try BookReadingProgressRecord
                .filter(BookReadingProgressRecord.Columns.bookID == bookID.uuidString)
                .filter(BookReadingProgressRecord.Columns.userID == userID)
                .fetchOne(database)?
                .domainModel()
        }
    }

    func saveProgress(_ progress: BookReadingProgress) throws {
        var record: BookReadingProgressRecord = BookReadingProgressRecord(progress: progress)
        try self.database.queue.write { database in
            try record.save(database)
        }
    }

    func deleteProgress(bookID: UUID, userID: String) throws {
        try self.database.queue.write { database in
            try database.execute(
                sql: "DELETE FROM \(BookReadingProgressRecord.databaseTableName) WHERE bookID = ? AND userID = ?",
                arguments: [bookID.uuidString, userID]
            )
        }
    }
}
