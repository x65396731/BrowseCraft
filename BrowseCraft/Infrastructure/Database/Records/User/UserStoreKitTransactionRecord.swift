import Foundation
import GRDB

// 中文注释：UserStoreKitTransactionRecord 是 user_storekit_transactions 表的一行。
struct UserStoreKitTransactionRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName: String = "user_storekit_transactions"

    var userID: String
    var transactionID: String
    var originalTransactionID: String
    var productID: String
    var productType: String
    var environment: String
    var ownershipType: String
    var purchaseDate: Date
    var expirationDate: Date?
    var revocationDate: Date?
    var createdAt: Date

    init(transaction: UserStoreKitTransaction) {
        self.userID = transaction.userID
        self.transactionID = transaction.transactionID
        self.originalTransactionID = transaction.originalTransactionID
        self.productID = transaction.productID
        self.productType = transaction.productType
        self.environment = transaction.environment
        self.ownershipType = transaction.ownershipType
        self.purchaseDate = transaction.purchaseDate
        self.expirationDate = transaction.expirationDate
        self.revocationDate = transaction.revocationDate
        self.createdAt = transaction.createdAt
    }
}
