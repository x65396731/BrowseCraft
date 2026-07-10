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

    func hasProcessedStoreKitTransaction(userID: String, transactionID: String) throws -> Bool {
        return try self.database.queue.read { database in
            let count: Int = try UserStoreKitTransactionRecord
                .filter(
                    UserStoreKitTransactionRecord.Columns.userID == userID &&
                    UserStoreKitTransactionRecord.Columns.transactionID == transactionID
                )
                .fetchCount(database)
            return count > 0
        }
    }

    func saveUser(_ user: AppUser) throws {
        var record: AppUserRecord = AppUserRecord(user: user)

        try self.database.queue.write { database in
            try record.save(database)
        }
    }

    func saveUser(_ user: AppUser, storeKitTransaction: UserStoreKitTransaction) throws {
        var userRecord: AppUserRecord = AppUserRecord(user: user)
        var transactionRecord: UserStoreKitTransactionRecord = UserStoreKitTransactionRecord(
            transaction: storeKitTransaction
        )

        try self.database.queue.write { database in
            try userRecord.save(database)
            try transactionRecord.save(database)
        }
    }
}
