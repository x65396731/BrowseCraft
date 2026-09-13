import Foundation
import GRDB

// 中文注释：GRDBLocalBookRepository 通过 SQLite 保存本地书清单；save 按主键 upsert。

final class GRDBLocalBookRepository: LocalBookRepository {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func fetchBooks(userID: String) throws -> [LocalBook] {
        return try self.database.queue.read { database in
            return try LocalBookRecord
                .filter(LocalBookRecord.Columns.userID == userID)
                .order(LocalBookRecord.Columns.importedAt.desc)
                .fetchAll(database)
                .compactMap { $0.domainModel() }
        }
    }

    func fetchBook(id: UUID, userID: String) throws -> LocalBook? {
        return try self.database.queue.read { database in
            return try LocalBookRecord
                .filter(LocalBookRecord.Columns.id == id.uuidString)
                .filter(LocalBookRecord.Columns.userID == userID)
                .fetchOne(database)?
                .domainModel()
        }
    }

    func fetchBook(fileSHA256: String, userID: String) throws -> LocalBook? {
        return try self.database.queue.read { database in
            return try LocalBookRecord
                .filter(LocalBookRecord.Columns.fileSHA256 == fileSHA256)
                .filter(LocalBookRecord.Columns.userID == userID)
                .order(LocalBookRecord.Columns.importedAt.desc)
                .fetchOne(database)?
                .domainModel()
        }
    }

    func saveBook(_ book: LocalBook) throws {
        var record: LocalBookRecord = LocalBookRecord(book: book)
        try self.database.queue.write { database in
            try record.save(database)
        }
    }

    func deleteBook(id: UUID, userID: String) throws {
        try self.database.queue.write { database in
            try database.execute(
                sql: "DELETE FROM \(LocalBookRecord.databaseTableName) WHERE id = ? AND userID = ?",
                arguments: [id.uuidString, userID]
            )
        }
    }
}
