import Foundation

// 中文注释：UserStoreKitTransaction 记录本地用户和 StoreKit 交易之间的一对多关联。
struct UserStoreKitTransaction: Hashable {
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
}
