import Foundation
import GRDB

// 中文注释：AppUserRecord 是 users 表的一行。

/// 中文注释：当前只保存本地用户根信息，后续历史表通过 userID 关联到它。
struct AppUserRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName: String = "users"

    var id: String
    var displayName: String?
    var hasRemovedAds: Bool
    var pendingAdPoints: Int
    var siteSlotLimit: Int
    var purchasedSiteSlots: Int
    var vipExpiresAt: Date?
    var processedStoreKitTransactionIDsJSON: String?
    var lastStoreKitTransactionID: String?
    var lastStoreKitOriginalTransactionID: String?
    var lastStoreKitProductID: String?
    var lastStoreKitProductType: String?
    var lastStoreKitEnvironment: String?
    var lastStoreKitOwnershipType: String?
    var lastStoreKitPurchaseDate: Date?
    var lastStoreKitExpirationDate: Date?
    var lastStoreKitRevocationDate: Date?
    var createdAt: Date
    var updatedAt: Date

    init(user: AppUser) {
        self.id = user.id
        self.displayName = user.displayName
        self.hasRemovedAds = user.hasRemovedAds
        self.pendingAdPoints = user.pendingAdPoints
        self.siteSlotLimit = user.siteSlotLimit
        self.purchasedSiteSlots = user.purchasedSiteSlots
        self.vipExpiresAt = user.vipExpiresAt
        self.processedStoreKitTransactionIDsJSON = user.processedStoreKitTransactionIDsJSON
        self.lastStoreKitTransactionID = user.lastStoreKitTransactionID
        self.lastStoreKitOriginalTransactionID = user.lastStoreKitOriginalTransactionID
        self.lastStoreKitProductID = user.lastStoreKitProductID
        self.lastStoreKitProductType = user.lastStoreKitProductType
        self.lastStoreKitEnvironment = user.lastStoreKitEnvironment
        self.lastStoreKitOwnershipType = user.lastStoreKitOwnershipType
        self.lastStoreKitPurchaseDate = user.lastStoreKitPurchaseDate
        self.lastStoreKitExpirationDate = user.lastStoreKitExpirationDate
        self.lastStoreKitRevocationDate = user.lastStoreKitRevocationDate
        self.createdAt = user.createdAt
        self.updatedAt = user.updatedAt
    }

    func domainModel() -> AppUser {
        return AppUser(
            id: self.id,
            displayName: self.displayName,
            hasRemovedAds: self.hasRemovedAds,
            pendingAdPoints: self.pendingAdPoints,
            siteSlotLimit: self.siteSlotLimit,
            purchasedSiteSlots: self.purchasedSiteSlots,
            vipExpiresAt: self.vipExpiresAt,
            processedStoreKitTransactionIDsJSON: self.processedStoreKitTransactionIDsJSON,
            lastStoreKitTransactionID: self.lastStoreKitTransactionID,
            lastStoreKitOriginalTransactionID: self.lastStoreKitOriginalTransactionID,
            lastStoreKitProductID: self.lastStoreKitProductID,
            lastStoreKitProductType: self.lastStoreKitProductType,
            lastStoreKitEnvironment: self.lastStoreKitEnvironment,
            lastStoreKitOwnershipType: self.lastStoreKitOwnershipType,
            lastStoreKitPurchaseDate: self.lastStoreKitPurchaseDate,
            lastStoreKitExpirationDate: self.lastStoreKitExpirationDate,
            lastStoreKitRevocationDate: self.lastStoreKitRevocationDate,
            createdAt: self.createdAt,
            updatedAt: self.updatedAt
        )
    }
}
