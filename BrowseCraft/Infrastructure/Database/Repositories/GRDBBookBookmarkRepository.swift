import Foundation
import GRDB

// 中文注释：GRDBBookBookmarkRepository 保存书签，列表按创建时间倒序。

final class GRDBBookBookmarkRepository: BookBookmarkRepository {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func fetchBookmarks(bookID: UUID, userID: String) throws -> [BookBookmark] {
        return try self.database.queue.read { database in
            return try BookBookmarkRecord
                .filter(BookBookmarkRecord.Columns.bookID == bookID.uuidString)
                .filter(BookBookmarkRecord.Columns.userID == userID)
                .order(BookBookmarkRecord.Columns.createdAt.desc)
                .fetchAll(database)
                .compactMap { $0.domainModel() }
        }
    }

    func saveBookmark(_ bookmark: BookBookmark) throws {
        var record: BookBookmarkRecord = BookBookmarkRecord(bookmark: bookmark)
        try self.database.queue.write { database in
            try record.save(database)
        }
    }

    func deleteBookmark(id: UUID, userID: String) throws {
        try self.database.queue.write { database in
            try database.execute(
                sql: "DELETE FROM \(BookBookmarkRecord.databaseTableName) WHERE id = ? AND userID = ?",
                arguments: [id.uuidString, userID]
            )
        }
    }
}
