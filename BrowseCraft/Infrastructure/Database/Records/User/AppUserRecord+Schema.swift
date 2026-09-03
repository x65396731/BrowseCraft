import Foundation
@preconcurrency import GRDB

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

    /// 中文注释：仅供仍使用旧身份 fixture 的隔离测试调用；App 启动路径不得创建此用户。
    static func insertLocalDefaultUser(in database: Database) throws {
        try Self.insertUser(
            id: AppUser.localDefaultID,
            displayName: "Local Default",
            in: database
        )
    }

    /// 中文注释：这里只创建真实业务 AppUser；CloudAccountScope 不得再调用此方法。
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
