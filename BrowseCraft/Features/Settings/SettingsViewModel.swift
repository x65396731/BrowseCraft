import Combine
import Foundation
import StoreKit

// 中文注释：SettingsViewModel 负责设置页中需要调用应用服务的状态与动作。

/// 中文注释：SettingsViewModel 把 Settings UI 与 Nuke 缓存配置隔离，View 不直接操作缓存服务。
final class SettingsViewModel: ObservableObject {
    @Published private(set) var imageCacheSettings: ImageCacheSettings
    @Published var cacheErrorMessage: String?
    @Published var cacheStatusMessage: String?

    private let imageCacheConfigurator: ImageCacheConfigurator
    private let appUserRepository: AppUserRepository

    init(
        imageCacheConfigurator: ImageCacheConfigurator,
        appUserRepository: AppUserRepository? = nil
    ) {
        self.imageCacheConfigurator = imageCacheConfigurator
        self.appUserRepository = appUserRepository ?? InMemoryDefaultAppUserRepository()
        self.imageCacheSettings = ImageCacheSettings.load()
    }

    @MainActor
    func selectImageCacheLimit(_ limit: ImageCacheLimitOption) {
        let settings: ImageCacheSettings = ImageCacheSettings(limit: limit)

        do {
            try self.imageCacheConfigurator.apply(settings: settings)
            self.imageCacheConfigurator.trimConfiguredDataCacheIfNeeded(settings: settings)
            self.imageCacheSettings = settings
            self.cacheErrorMessage = nil
            self.cacheStatusMessage = nil
        } catch {
            #if DEBUG
            print("[BrowseCraftImageCache] settings update failed error=\(error)")
            #endif
            self.cacheErrorMessage = "Image cache settings could not be updated."
        }
    }

    @MainActor
    func clearImageCache() {
        self.imageCacheConfigurator.clearConfiguredCaches()
        self.cacheErrorMessage = nil
        // 中文注释：Nuke DataCache 的 removeAll 是异步写入队列动作，因此文案只承诺“已开始清理”。
        self.cacheStatusMessage = "Image cache clearing has started."

        #if DEBUG
        print("[BrowseCraftImageCache] clear cache requested")
        #endif
    }

    @MainActor
    func applyStoreKitPurchase(
        transaction: StoreKit.Transaction,
        plan: InAppPurchasePlan
    ) throws {
        let now: Date = Date()
        var user: AppUser = try self.appUserRepository.fetchUser(id: AppUser.localDefaultID) ?? AppUser(
            id: AppUser.localDefaultID,
            displayName: "Local Default",
            hasRemovedAds: false,
            pendingAdPoints: 0,
            createdAt: now,
            updatedAt: now
        )

        let transactionID: String = String(transaction.id)
        let hasProcessedTransaction: Bool = try self.appUserRepository.hasProcessedStoreKitTransaction(
            userID: user.id,
            transactionID: transactionID
        )
        let storeKitTransaction: UserStoreKitTransaction = self.makeUserStoreKitTransaction(
            transaction: transaction,
            userID: user.id,
            createdAt: now
        )

        self.recordStoreKitMetadata(transaction: transaction, user: &user)

        if hasProcessedTransaction == false && transaction.revocationDate == nil {
            self.applyEntitlement(plan: plan, user: &user, now: now)
        }

        user.updatedAt = now

        if hasProcessedTransaction {
            try self.appUserRepository.saveUser(user)
        } else {
            try self.appUserRepository.saveUser(user, storeKitTransaction: storeKitTransaction)
        }
    }

    private func applyEntitlement(plan: InAppPurchasePlan, user: inout AppUser, now: Date) {
        if plan.removesAds {
            user.hasRemovedAds = true
        }

        if plan.siteSlotIncrement > 0 {
            user.purchasedSiteSlots += plan.siteSlotIncrement
            user.siteSlotLimit += plan.siteSlotIncrement
        }

        if plan.vipMonthDuration > 0 {
            let baseDate: Date = max(user.vipExpiresAt ?? now, now)
            user.vipExpiresAt = Calendar.current.date(
                byAdding: .month,
                value: plan.vipMonthDuration,
                to: baseDate
            )
        }
    }

    private func recordStoreKitMetadata(transaction: StoreKit.Transaction, user: inout AppUser) {
        user.lastStoreKitTransactionID = String(transaction.id)
        user.lastStoreKitOriginalTransactionID = String(transaction.originalID)
        user.lastStoreKitProductID = transaction.productID
        user.lastStoreKitProductType = transaction.productType.rawValue
        user.lastStoreKitEnvironment = transaction.environment.rawValue
        user.lastStoreKitOwnershipType = transaction.ownershipType.rawValue
        user.lastStoreKitPurchaseDate = transaction.purchaseDate
        user.lastStoreKitExpirationDate = transaction.expirationDate
        user.lastStoreKitRevocationDate = transaction.revocationDate
    }

    private func makeUserStoreKitTransaction(
        transaction: StoreKit.Transaction,
        userID: String,
        createdAt: Date
    ) -> UserStoreKitTransaction {
        return UserStoreKitTransaction(
            userID: userID,
            transactionID: String(transaction.id),
            originalTransactionID: String(transaction.originalID),
            productID: transaction.productID,
            productType: transaction.productType.rawValue,
            environment: transaction.environment.rawValue,
            ownershipType: transaction.ownershipType.rawValue,
            purchaseDate: transaction.purchaseDate,
            expirationDate: transaction.expirationDate,
            revocationDate: transaction.revocationDate,
            createdAt: createdAt
        )
    }
}

private final class InMemoryDefaultAppUserRepository: AppUserRepository {
    private var user: AppUser?
    private var transactionIDs: Set<String> = []

    func fetchUser(id: String) throws -> AppUser? {
        return self.user
    }

    func hasProcessedStoreKitTransaction(userID: String, transactionID: String) throws -> Bool {
        return self.transactionIDs.contains("\(userID):\(transactionID)")
    }

    func saveUser(_ user: AppUser) throws {
        self.user = user
    }

    func saveUser(_ user: AppUser, storeKitTransaction: UserStoreKitTransaction) throws {
        self.user = user
        self.transactionIDs.insert("\(storeKitTransaction.userID):\(storeKitTransaction.transactionID)")
    }
}
