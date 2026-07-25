import Combine
import Foundation
import StoreKit

// 中文注释：SettingsViewModel 负责设置页中需要调用应用服务的状态与动作。

enum StoreKitTransactionIdentityError: Error, Equatable {
    case missingAppAccountToken
    case accountMismatch
}

enum StoreKitPortalPurchaseSubmissionError: Error, Equatable {
    case xcodeEnvironmentUnsupported
    case unsupportedEnvironment(String)
    case transactionProductMismatch
    case snapshotContractMismatch
    case purchasedProductMissing
}

struct StoreKitPortalEnvironmentMapper {
    static func map(
        _ environment: StoreKit.AppStore.Environment
    ) throws -> PortalPurchaseEnvironment {
        if environment == .sandbox {
            return .sandbox
        }
        if environment == .production {
            return .production
        }
        if environment == .xcode {
            throw StoreKitPortalPurchaseSubmissionError
                .xcodeEnvironmentUnsupported
        }
        throw StoreKitPortalPurchaseSubmissionError
            .unsupportedEnvironment(environment.rawValue)
    }
}

/// 中文注释：SettingsViewModel 把 Settings UI 与 Nuke 缓存配置隔离，View 不直接操作缓存服务。
final class SettingsViewModel: ObservableObject {
    @Published private(set) var imageCacheSettings: ImageCacheSettings
    @Published var cacheErrorMessage: String?
    @Published var cacheStatusMessage: String?
    @Published private(set) var diagnosticCode: String
    @Published private(set) var storeKitTransactionUpdateRevision: UInt64 = 0
    @Published private(set) var storeKitTransactionUpdateActiveProductIDs:
        Set<String>?

    private let imageCacheConfigurator: ImageCacheConfigurator
    private let appUserRepository: AppUserRepository
    private let activeAppUser: any ActiveAppUserProviding
    private let purchaseIdentityAuthorizer: StoreKitPurchaseIdentityAuthorizer
    private let portalPurchaseEntitlementRefreshCoordinator:
        PortalPurchaseEntitlementRefreshCoordinator
    private let diagnosticIdentityStore: DiagnosticIdentityStore

    init(
        imageCacheConfigurator: ImageCacheConfigurator,
        appUserRepository: AppUserRepository,
        activeAppUser: any ActiveAppUserProviding,
        purchaseIdentityAuthorizer: StoreKitPurchaseIdentityAuthorizer,
        portalPurchaseEntitlementRefreshCoordinator:
            PortalPurchaseEntitlementRefreshCoordinator,
        diagnosticIdentityStore: DiagnosticIdentityStore = .shared
    ) {
        self.imageCacheConfigurator = imageCacheConfigurator
        self.appUserRepository = appUserRepository
        self.activeAppUser = activeAppUser
        self.purchaseIdentityAuthorizer = purchaseIdentityAuthorizer
        self.portalPurchaseEntitlementRefreshCoordinator =
            portalPurchaseEntitlementRefreshCoordinator
        self.diagnosticIdentityStore = diagnosticIdentityStore
        self.imageCacheSettings = ImageCacheSettings.load()
        self.diagnosticCode = diagnosticIdentityStore.identity.diagnosticCode
    }

    @MainActor
    func refreshDiagnosticCode() {
        self.diagnosticCode = self.diagnosticIdentityStore.identity.diagnosticCode
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
            AppAnalytics.shared.logSettingChanged(
                name: "image_cache_limit",
                value: String(limit.megabytes)
            )
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
    func authorizeUserInitiatedStoreKitAction() async throws -> UUID {
        return try await self.purchaseIdentityAuthorizer
            .authorizeUserInitiatedStoreKitAction()
    }

    @MainActor
    func validateAuthorizedStoreKitUser(_ userID: UUID) async throws {
        try await self.purchaseIdentityAuthorizer.validateAuthorizedUser(userID)
    }

    @MainActor
    func submitStoreKitPurchase(
        transaction: StoreKit.Transaction,
        signedTransaction: String,
        plan: InAppPurchasePlan
    ) async throws -> Set<String> {
        let userID: UUID = self.activeAppUser.currentUserID
        IAPDiagnostics.notice(
            "event=purchase-submission-started " +
                "userHash=\(IAPDiagnostics.hash(userID)) " +
                "transactionHash=\(IAPDiagnostics.hash(transactionID: transaction.id)) " +
                "productID=\(transaction.productID) " +
                "storeKitEnvironment=\(transaction.environment.rawValue)"
        )
        try self.requireStoreKitTransactionOwner(
            transaction,
            userID: userID
        )
        guard transaction.productID == plan.productID else {
            throw StoreKitPortalPurchaseSubmissionError
                .transactionProductMismatch
        }

        let environment: PortalPurchaseEnvironment =
            try StoreKitPortalEnvironmentMapper.map(transaction.environment)
        let snapshot: PortalEntitlementSnapshot =
            try await self.portalPurchaseEntitlementRefreshCoordinator
                .refreshPurchasedEntitlements(
                    userID: userID,
                    environment: environment,
                    signedTransaction: signedTransaction
                )

        try await self.purchaseIdentityAuthorizer
            .validateAuthorizedUser(userID)
        try self.validatePortalSnapshot(
            snapshot,
            purchasedProductID: plan.productID
        )
        try self.applyPortalEntitlementSnapshot(
            snapshot,
            transaction: transaction
        )
        IAPDiagnostics.notice(
            "event=purchase-submission-completed " +
                "transactionHash=\(IAPDiagnostics.hash(transactionID: transaction.id)) " +
                "environment=\(environment.rawValue) " +
                "revision=\(snapshot.revision)"
        )
        return snapshot.activeProductIDs
    }

    @MainActor
    func processStoreKitTransactionUpdate(
        transaction: StoreKit.Transaction,
        signedTransaction: String,
        plan: InAppPurchasePlan
    ) async throws -> Set<String> {
        let userID: UUID = self.activeAppUser.currentUserID
        IAPDiagnostics.notice(
            "event=transaction-update-submission-started " +
                "userHash=\(IAPDiagnostics.hash(userID)) " +
                "transactionHash=\(IAPDiagnostics.hash(transactionID: transaction.id)) " +
                "productID=\(transaction.productID) " +
                "storeKitEnvironment=\(transaction.environment.rawValue) " +
                "isRevoked=\(transaction.revocationDate != nil)"
        )
        try self.requireStoreKitTransactionOwner(
            transaction,
            userID: userID
        )
        guard transaction.productID == plan.productID else {
            throw StoreKitPortalPurchaseSubmissionError
                .transactionProductMismatch
        }

        let environment: PortalPurchaseEnvironment =
            try StoreKitPortalEnvironmentMapper.map(transaction.environment)
        let snapshot: PortalEntitlementSnapshot =
            try await self.portalPurchaseEntitlementRefreshCoordinator
                .refreshUpdatedEntitlements(
                    userID: userID,
                    environment: environment,
                    signedTransaction: signedTransaction
                )

        try await self.purchaseIdentityAuthorizer
            .validateAuthorizedUser(userID)
        try self.validatePortalSnapshot(
            snapshot,
            updatedProductID: plan.productID,
            isRevoked: transaction.revocationDate != nil
        )
        try self.applyPortalEntitlementSnapshot(
            snapshot,
            transaction: transaction
        )
        IAPDiagnostics.notice(
            "event=transaction-update-submission-completed " +
                "transactionHash=\(IAPDiagnostics.hash(transactionID: transaction.id)) " +
                "environment=\(environment.rawValue) " +
                "revision=\(snapshot.revision)"
        )
        return snapshot.activeProductIDs
    }

    @MainActor
    func recordStoreKitTransactionUpdate(
        activeProductIDs: Set<String>?
    ) {
        self.storeKitTransactionUpdateActiveProductIDs = activeProductIDs
        self.storeKitTransactionUpdateRevision &+= 1
    }

    @MainActor
    func restoreStoreKitPurchases(
        for authorizedUserID: UUID
    ) async throws -> Set<String>? {
        IAPDiagnostics.notice(
            "event=restore-started " +
                "userHash=\(IAPDiagnostics.hash(authorizedUserID))"
        )
        try await self.purchaseIdentityAuthorizer
            .validateAuthorizedUser(authorizedUserID)
        try await AppStore.sync()
        IAPDiagnostics.notice("event=restore-app-store-sync-completed")

        var restorableTransactions: [RestorableStoreKitTransaction] = []
        var unverifiedCount: Int = 0
        var unsupportedProductCount: Int = 0
        var revokedCount: Int = 0
        var identityMismatchCount: Int = 0
        for await verification in StoreKit.Transaction.currentEntitlements {
            try Task.checkCancellation()
            guard case .verified(let transaction) = verification else {
                unverifiedCount += 1
                continue
            }
            guard let plan: InAppPurchasePlan =
                InAppPurchasePlan.plansByProductID[transaction.productID],
                  plan.isRestorable else {
                unsupportedProductCount += 1
                continue
            }
            guard transaction.revocationDate == nil else {
                revokedCount += 1
                continue
            }
            do {
                try self.requireStoreKitTransactionOwner(
                    transaction,
                    userID: authorizedUserID
                )
            } catch is StoreKitTransactionIdentityError {
                identityMismatchCount += 1
                continue
            }

            restorableTransactions.append(
                RestorableStoreKitTransaction(
                    transaction: transaction,
                    signedTransaction: verification.jwsRepresentation,
                    plan: plan,
                    environment: try StoreKitPortalEnvironmentMapper.map(
                        transaction.environment
                    )
                )
            )
        }
        IAPDiagnostics.notice(
            "event=restore-entitlements-collected " +
                "acceptedCount=\(restorableTransactions.count) " +
                "unverifiedCount=\(unverifiedCount) " +
                "unsupportedProductCount=\(unsupportedProductCount) " +
                "revokedCount=\(revokedCount) " +
                "identityMismatchCount=\(identityMismatchCount)"
        )

        restorableTransactions.sort { lhs, rhs in
            return lhs.transaction.purchaseDate < rhs.transaction.purchaseDate
        }

        try await self.purchaseIdentityAuthorizer
            .validateAuthorizedUser(authorizedUserID)
        guard let environment: PortalPurchaseEnvironment =
            restorableTransactions.first?.environment else {
            IAPDiagnostics.notice(
                "event=restore-completed outcome=no-restorable-transactions"
            )
            return nil
        }
        guard restorableTransactions.allSatisfy({ candidate in
            candidate.environment == environment
        }) else {
            IAPDiagnostics.error(
                "event=restore-failed reason=mixed-environments"
            )
            throw StoreKitPortalPurchaseSubmissionError
                .snapshotContractMismatch
        }

        let snapshot: PortalEntitlementSnapshot =
            try await self.portalPurchaseEntitlementRefreshCoordinator
                .restoreEntitlements(
                    userID: authorizedUserID,
                    environment: environment,
                    signedTransactions: restorableTransactions.map(
                        \.signedTransaction
                    ),
                    recoveryProof: restorableTransactions[0].signedTransaction
                )
        try await self.purchaseIdentityAuthorizer
            .validateAuthorizedUser(authorizedUserID)
        try self.validatePortalSnapshot(
            snapshot,
            restoredProductIDs: Set(
                restorableTransactions.map { candidate in
                    candidate.plan.productID
                }
            )
        )
        try self.applyPortalEntitlementSnapshot(
            snapshot,
            transactions: restorableTransactions.map(\.transaction)
        )
        for candidate: RestorableStoreKitTransaction in restorableTransactions {
            await candidate.transaction.finish()
        }
        IAPDiagnostics.notice(
            "event=restore-completed " +
                "environment=\(environment.rawValue) " +
                "transactionCount=\(restorableTransactions.count) " +
                "revision=\(snapshot.revision)"
        )
        return snapshot.activeProductIDs
    }

    private func requireStoreKitTransactionOwner(
        _ transaction: StoreKit.Transaction,
        userID: UUID
    ) throws {
        guard let appAccountToken: UUID = transaction.appAccountToken else {
            IAPDiagnostics.error(
                "event=transaction-owner-check-failed " +
                    "reason=app-account-token-missing " +
                    "transactionHash=\(IAPDiagnostics.hash(transactionID: transaction.id))"
            )
            throw StoreKitTransactionIdentityError.missingAppAccountToken
        }
        guard appAccountToken == userID else {
            IAPDiagnostics.error(
                "event=transaction-owner-check-failed " +
                    "reason=app-account-token-mismatch " +
                    "transactionHash=\(IAPDiagnostics.hash(transactionID: transaction.id)) " +
                    "expectedUserHash=\(IAPDiagnostics.hash(userID)) " +
                    "actualUserHash=\(IAPDiagnostics.hash(appAccountToken))"
            )
            throw StoreKitTransactionIdentityError.accountMismatch
        }
    }

    private func validatePortalSnapshot(
        _ snapshot: PortalEntitlementSnapshot,
        purchasedProductID: String
    ) throws {
        let supportedProductIDs: Set<String> = Set(
            InAppPurchasePlan.activePlans.map(\.productID)
        )
        guard snapshot.userID == self.activeAppUser.currentUserID,
              snapshot.includedSiteSlots ==
                SourceSlotPolicy.includedSiteSlotCount,
              snapshot.activeProductIDs.isSubset(of: supportedProductIDs) else {
            throw StoreKitPortalPurchaseSubmissionError
                .snapshotContractMismatch
        }
        guard snapshot.activeProductIDs.contains(purchasedProductID) else {
            throw StoreKitPortalPurchaseSubmissionError
                .purchasedProductMissing
        }
    }

    private func validatePortalSnapshot(
        _ snapshot: PortalEntitlementSnapshot,
        restoredProductIDs: Set<String>
    ) throws {
        let supportedProductIDs: Set<String> = Set(
            InAppPurchasePlan.activePlans.map(\.productID)
        )
        guard snapshot.userID == self.activeAppUser.currentUserID,
              snapshot.includedSiteSlots ==
                SourceSlotPolicy.includedSiteSlotCount,
              snapshot.activeProductIDs.isSubset(of: supportedProductIDs),
              restoredProductIDs.isSubset(of: snapshot.activeProductIDs) else {
            throw StoreKitPortalPurchaseSubmissionError
                .snapshotContractMismatch
        }
    }

    private func validatePortalSnapshot(
        _ snapshot: PortalEntitlementSnapshot,
        updatedProductID: String,
        isRevoked: Bool
    ) throws {
        let supportedProductIDs: Set<String> = Set(
            InAppPurchasePlan.activePlans.map(\.productID)
        )
        guard snapshot.userID == self.activeAppUser.currentUserID,
              snapshot.includedSiteSlots ==
                SourceSlotPolicy.includedSiteSlotCount,
              snapshot.activeProductIDs.isSubset(of: supportedProductIDs) else {
            throw StoreKitPortalPurchaseSubmissionError
                .snapshotContractMismatch
        }

        let containsUpdatedProduct: Bool =
            snapshot.activeProductIDs.contains(updatedProductID)
        guard containsUpdatedProduct != isRevoked else {
            throw StoreKitPortalPurchaseSubmissionError
                .snapshotContractMismatch
        }
    }

    private func applyPortalEntitlementSnapshot(
        _ snapshot: PortalEntitlementSnapshot,
        transaction: StoreKit.Transaction
    ) throws {
        try self.applyPortalEntitlementSnapshot(
            snapshot,
            transactions: [transaction]
        )
    }

    private func applyPortalEntitlementSnapshot(
        _ snapshot: PortalEntitlementSnapshot,
        transactions: [StoreKit.Transaction]
    ) throws {
        let now: Date = Date()
        let userID: String = snapshot.userID.uuidString
        var user: AppUser = try self.appUserRepository.fetchUser(id: userID) ??
            AppUser(
                id: userID,
                displayName: nil,
                hasRemovedAds: false,
                pendingAdPoints: 0,
                createdAt: now,
                updatedAt: now
            )

        user.hasRemovedAds = snapshot.hasRemovedAds
        user.purchasedSiteSlots = snapshot.purchasedSiteSlots
        user.siteSlotLimit = snapshot.siteSlotLimit
        user.updatedAt = now
        if let latestTransaction: StoreKit.Transaction =
            transactions.max(by: { lhs, rhs in
                lhs.purchaseDate < rhs.purchaseDate
            }) {
            self.recordStoreKitMetadata(
                transaction: latestTransaction,
                user: &user
            )
        }

        var newTransactions: [UserStoreKitTransaction] = []
        for transaction: StoreKit.Transaction in transactions {
            let transactionID: String = String(transaction.id)
            guard try self.appUserRepository.hasProcessedStoreKitTransaction(
                userID: userID,
                transactionID: transactionID
            ) == false else {
                continue
            }
            newTransactions.append(
                self.makeUserStoreKitTransaction(
                    transaction: transaction,
                    userID: userID,
                    createdAt: now
                )
            )
        }
        try self.appUserRepository.saveUser(
            user,
            storeKitTransactions: newTransactions
        )
        IAPDiagnostics.notice(
            "event=entitlement-snapshot-persisted " +
                "environment=\(snapshot.environment.rawValue) " +
                "revision=\(snapshot.revision) " +
                "transactionCount=\(transactions.count) " +
                "newTransactionCount=\(newTransactions.count) " +
                "siteSlotLimit=\(snapshot.siteSlotLimit) " +
                "hasRemovedAds=\(snapshot.hasRemovedAds)"
        )
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

private struct RestorableStoreKitTransaction {
    let transaction: StoreKit.Transaction
    let signedTransaction: String
    let plan: InAppPurchasePlan
    let environment: PortalPurchaseEnvironment
}
