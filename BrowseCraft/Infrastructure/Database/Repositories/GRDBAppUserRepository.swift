import Foundation
import GRDB

// 中文注释：GRDBAppUserRepository 通过 SQLite 保存本地用户状态。
final class GRDBAppUserRepository:
    AppUserRepository,
    PortalEntitlementCacheResetting,
    @unchecked Sendable {
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

    func saveUser(
        _ user: AppUser,
        storeKitTransactions: [UserStoreKitTransaction]
    ) throws {
        var userRecord: AppUserRecord = AppUserRecord(user: user)
        let transactionRecords: [UserStoreKitTransactionRecord] =
            storeKitTransactions.map { transaction in
                return UserStoreKitTransactionRecord(transaction: transaction)
            }

        try self.database.queue.write { database in
            try userRecord.save(database)
            for var transactionRecord: UserStoreKitTransactionRecord in transactionRecords {
                try transactionRecord.save(database)
            }
        }
    }

    func resetPortalEntitlements(for userID: UUID) throws {
        let databaseUserID: String = userID.uuidString
        try self.database.queue.write { database in
            try AppUserRecord.insertUser(id: databaseUserID, in: database)
            guard var record: AppUserRecord = try AppUserRecord.fetchOne(
                database,
                key: databaseUserID
            ) else {
                return
            }
            record.hasRemovedAds = false
            record.purchasedSiteSlots = 0
            record.siteSlotLimit = SourceSlotPolicy.includedSiteSlotCount
            record.vipExpiresAt = nil
            record.updatedAt = Date()
            try record.save(database)
        }
    }
}
