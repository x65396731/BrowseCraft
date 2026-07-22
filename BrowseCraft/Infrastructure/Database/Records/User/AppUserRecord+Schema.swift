import Foundation
import GRDB

extension AppUserRecord {
    enum Columns {
        static let id: Column = Column("id")
        static let displayName: Column = Column("displayName")
        static let hasRemovedAds: Column = Column("hasRemovedAds")
        static let pendingAdPoints: Column = Column("pendingAdPoints")
        static let siteSlotLimit: Column = Column("siteSlotLimit")
        static let purchasedSiteSlots: Column = Column("purchasedSiteSlots")
        static let vipExpiresAt: Column = Column("vipExpiresAt")
        static let processedStoreKitTransactionIDsJSON: Column = Column("processedStoreKitTransactionIDsJSON")
        static let lastStoreKitTransactionID: Column = Column("lastStoreKitTransactionID")
        static let lastStoreKitOriginalTransactionID: Column = Column("lastStoreKitOriginalTransactionID")
        static let lastStoreKitProductID: Column = Column("lastStoreKitProductID")
        static let lastStoreKitProductType: Column = Column("lastStoreKitProductType")
        static let lastStoreKitEnvironment: Column = Column("lastStoreKitEnvironment")
        static let lastStoreKitOwnershipType: Column = Column("lastStoreKitOwnershipType")
        static let lastStoreKitPurchaseDate: Column = Column("lastStoreKitPurchaseDate")
        static let lastStoreKitExpirationDate: Column = Column("lastStoreKitExpirationDate")
        static let lastStoreKitRevocationDate: Column = Column("lastStoreKitRevocationDate")
        static let createdAt: Column = Column("createdAt")
        static let updatedAt: Column = Column("updatedAt")
    }

    /// 中文注释：users 是本地业务用户根表，保存权益快照和最近一次 StoreKit 交易摘要。
    /// 中文注释：完整交易明细放在 user_storekit_transactions，避免 users 表无限增长。
    static func createTable(in database: Database) throws {
        try database.create(table: Self.databaseTableName, ifNotExists: true) { table in
            table.column("id", .text).primaryKey()
            table.column("displayName", .text)
            table.column("hasRemovedAds", .boolean).notNull().defaults(to: false)
            table.column("pendingAdPoints", .integer).notNull().defaults(to: 0)
            table.column("siteSlotLimit", .integer).notNull().defaults(to: 1)
            table.column("purchasedSiteSlots", .integer).notNull().defaults(to: 0)
            table.column("vipExpiresAt", .datetime)
            table.column("processedStoreKitTransactionIDsJSON", .text)
            table.column("lastStoreKitTransactionID", .text)
            table.column("lastStoreKitOriginalTransactionID", .text)
            table.column("lastStoreKitProductID", .text)
            table.column("lastStoreKitProductType", .text)
            table.column("lastStoreKitEnvironment", .text)
            table.column("lastStoreKitOwnershipType", .text)
            table.column("lastStoreKitPurchaseDate", .datetime)
            table.column("lastStoreKitExpirationDate", .datetime)
            table.column("lastStoreKitRevocationDate", .datetime)
            table.column("createdAt", .datetime).notNull()
            table.column("updatedAt", .datetime).notNull()
        }
    }

    /// 中文注释：当前没有 users 专用索引；主键 id 已覆盖本地默认用户读取。
    static func createIndexes(in database: Database) throws {
        _ = database
    }

    /// 中文注释：保证本地默认空间存在，供未绑定 iCloud 账户时正常离线使用。
    static func insertLocalDefaultUser(in database: Database) throws {
        try Self.insertUser(
            id: AppUser.localDefaultID,
            displayName: "Local Default",
            in: database
        )
    }

    /// 中文注释：Cloud account scope 也是本地业务用户根，但不保存或展示真实 Apple 账户信息。
    static func insertUser(
        id: String,
        displayName: String? = nil,
        in database: Database
    ) throws {
        let now: Date = Date()

        try database.execute(
            sql: """
            INSERT OR IGNORE INTO \(Self.databaseTableName)
                (
                    id,
                    displayName,
                    hasRemovedAds,
                    pendingAdPoints,
                    siteSlotLimit,
                    purchasedSiteSlots,
                    vipExpiresAt,
                    processedStoreKitTransactionIDsJSON,
                    lastStoreKitTransactionID,
                    lastStoreKitOriginalTransactionID,
                    lastStoreKitProductID,
                    lastStoreKitProductType,
                    lastStoreKitEnvironment,
                    lastStoreKitOwnershipType,
                    lastStoreKitPurchaseDate,
                    lastStoreKitExpirationDate,
                    lastStoreKitRevocationDate,
                    createdAt,
                    updatedAt
                )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                id,
                displayName,
                false,
                0,
                1,
                0,
                DatabaseValue.null,
                DatabaseValue.null,
                DatabaseValue.null,
                DatabaseValue.null,
                DatabaseValue.null,
                DatabaseValue.null,
                DatabaseValue.null,
                DatabaseValue.null,
                DatabaseValue.null,
                DatabaseValue.null,
                DatabaseValue.null,
                now,
                now
            ]
        )
    }
}
