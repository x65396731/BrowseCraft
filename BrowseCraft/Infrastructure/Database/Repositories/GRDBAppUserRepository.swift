import Foundation
import GRDB

// 中文注释：GRDBAppUserRepository 通过 SQLite 保存本地用户状态。
final class GRDBAppUserRepository: AppUserRepository {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func fetchUser(id: String) throws -> AppUser? {
        return try self.database.queue.read { database in
            return try AppUserRecord.fetchOne(database, key: id)?.domainModel()
        }
    }

    func saveUser(_ user: AppUser) throws {
        var record: AppUserRecord = AppUserRecord(user: user)

        try self.database.queue.write { database in
            try record.save(database)
        }
    }
}
