@preconcurrency import GRDB

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
}
