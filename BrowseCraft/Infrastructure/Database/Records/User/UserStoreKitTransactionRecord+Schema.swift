import GRDB

extension UserStoreKitTransactionRecord {
    enum Columns {
        static let userID: Column = Column("userID")
        static let transactionID: Column = Column("transactionID")
        static let originalTransactionID: Column = Column("originalTransactionID")
        static let productID: Column = Column("productID")
        static let productType: Column = Column("productType")
        static let environment: Column = Column("environment")
        static let ownershipType: Column = Column("ownershipType")
        static let purchaseDate: Column = Column("purchaseDate")
        static let expirationDate: Column = Column("expirationDate")
        static let revocationDate: Column = Column("revocationDate")
        static let createdAt: Column = Column("createdAt")
    }

    /// 中文注释：user_storekit_transactions 保存用户处理过的 StoreKit 交易明细，用于去重和重建权益。
    /// 中文注释：主键 userID + transactionID 保证同一用户同一交易只应用一次。
    static func createTable(in database: Database) throws {
        try database.create(table: Self.databaseTableName, ifNotExists: true) { table in
            table.column("userID", .text)
                .notNull()
                .references(AppUserRecord.databaseTableName, column: "id", onDelete: .cascade)
            table.column("transactionID", .text).notNull()
            table.column("originalTransactionID", .text).notNull()
            table.column("productID", .text).notNull()
            table.column("productType", .text).notNull()
            table.column("environment", .text).notNull()
            table.column("ownershipType", .text).notNull()
            table.column("purchaseDate", .datetime).notNull()
            table.column("expirationDate", .datetime)
            table.column("revocationDate", .datetime)
            table.column("createdAt", .datetime).notNull()
            table.primaryKey(["userID", "transactionID"])
        }
    }

    /// 中文注释：originalTransactionID 用于查订阅链，productID + purchaseDate 用于按商品回看购买记录。
    static func createIndexes(in database: Database) throws {
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_user_storekit_transactions_original_transaction
            ON \(Self.databaseTableName)(userID, originalTransactionID)
            """
        )
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_user_storekit_transactions_product
            ON \(Self.databaseTableName)(userID, productID, purchaseDate DESC)
            """
        )
    }
}
