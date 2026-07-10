import Foundation

// 中文注释：AppUser 是本地数据库历史记录的用户根模型。

/// 中文注释：当前 MVP 可以只有本地默认用户，但历史表必须显式挂到 userID 下。
struct AppUser: Identifiable, Hashable {
    static let localDefaultID: String = "local.default"

    var id: String
    var displayName: String?
    var hasRemovedAds: Bool
    var pendingAdPoints: Int
    var siteSlotLimit: Int = 1
    var purchasedSiteSlots: Int = 0
    var vipExpiresAt: Date? = nil
    var processedStoreKitTransactionIDsJSON: String? = nil
    var lastStoreKitTransactionID: String? = nil
    var lastStoreKitOriginalTransactionID: String? = nil
    var lastStoreKitProductID: String? = nil
    var lastStoreKitProductType: String? = nil
    var lastStoreKitEnvironment: String? = nil
    var lastStoreKitOwnershipType: String? = nil
    var lastStoreKitPurchaseDate: Date? = nil
    var lastStoreKitExpirationDate: Date? = nil
    var lastStoreKitRevocationDate: Date? = nil
    var createdAt: Date
    var updatedAt: Date
}
