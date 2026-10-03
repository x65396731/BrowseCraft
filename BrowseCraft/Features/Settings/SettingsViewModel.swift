import Observation
import Foundation
import StoreKit

// 中文注释：SettingsViewModel 负责设置页中需要调用应用服务的状态与动作。

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
@MainActor
@Observable
final class SettingsViewModel {
    private(set) var imageCacheSettings: ImageCacheSettings
    var cacheErrorMessage: String?
    /// 缓存页用量卡；nil = 正在计算。
    private(set) var imageCacheUsage: ImageCacheUsage?
    private(set) var isClearingCache: Bool = false
    /// 刚清除释放的字节数，缓存页显示「已清除，释放 N」约 3 秒。
    private(set) var lastClearedBytes: Int?
    private var clearResultToken: Int = 0
    private(set) var diagnosticCode: String
    private(set) var storeKitTransactionUpdateRevision: UInt64 = 0
    private(set) var storeKitTransactionUpdateActiveProductIDs:
        Set<String>?
    private(set) var isPortalAuthenticated: Bool = false
    private(set) var isPortalAccountActionInFlight: Bool = false
    var portalAccountErrorMessage: String?
    /// 其他页面（来源页「更多位置」）请求打开高级版购买入口；设置页出现时消费。
    private(set) var isInAppPurchaseRequested: Bool = false

    private let imageCacheManager: any ImageCacheManaging
    private let purchaseCoordinator: PortalPurchaseCoordinator
    private let diagnosticIdentityStore: DiagnosticIdentityStore
    private let portalSignInAction: @MainActor () async throws -> UUID
    private let portalSignOutAction: () async throws -> Void
    private let portalSessionSnapshotAction: () async -> PortalSessionSnapshot?
    /// 设计书第 30 节：账号区显示 coin 余额；nil 即未接线（测试替身）。
    let coinWalletStore: CoinWalletStore?

    init(
        imageCacheManager: any ImageCacheManaging,
        purchaseCoordinator: PortalPurchaseCoordinator,
        diagnosticIdentityStore: DiagnosticIdentityStore = .shared,
        portalSignInAction: @escaping @MainActor () async throws -> UUID = {
            throw StoreKitPurchaseIdentityAuthorizationError.signInRequired
        },
        portalSignOutAction: @escaping () async throws -> Void = {},
        portalSessionSnapshotAction: @escaping () async -> PortalSessionSnapshot? = {
            return nil
        },
        coinWalletStore: CoinWalletStore? = nil
    ) {
        self.imageCacheManager = imageCacheManager
        self.purchaseCoordinator = purchaseCoordinator
        self.diagnosticIdentityStore = diagnosticIdentityStore
        self.portalSignInAction = portalSignInAction
        self.portalSignOutAction = portalSignOutAction
        self.portalSessionSnapshotAction = portalSessionSnapshotAction
        self.coinWalletStore = coinWalletStore
        self.imageCacheSettings = ImageCacheSettings.load()
        self.diagnosticCode = diagnosticIdentityStore.identity.diagnosticCode
    }

    @MainActor
    func requestInAppPurchase() {
        self.isInAppPurchaseRequested = true
    }

    func consumeInAppPurchaseRequest() {
        self.isInAppPurchaseRequested = false
    }

    func refreshDiagnosticCode() {
        self.diagnosticCode = self.diagnosticIdentityStore.identity.diagnosticCode
    }

    @MainActor
    func refreshPortalAccountStatus() async {
        let snapshot: PortalSessionSnapshot? =
            await self.portalSessionSnapshotAction()
        self.isPortalAuthenticated = snapshot?.status == .authenticated
    }

    @MainActor
    func togglePortalAccount() async {
        guard self.isPortalAccountActionInFlight == false else {
            return
        }
        self.isPortalAccountActionInFlight = true
        self.portalAccountErrorMessage = nil
        defer {
            self.isPortalAccountActionInFlight = false
        }

        do {
            if self.isPortalAuthenticated {
                try await self.portalSignOutAction()
            } else {
                _ = try await self.portalSignInAction()
            }
            await self.refreshPortalAccountStatus()
        } catch let error as AppleSignInAuthorizationError
            where error == .cancelled {
            await self.refreshPortalAccountStatus()
        } catch {
            self.portalAccountErrorMessage = self.isPortalAuthenticated
                ? NSLocalizedString("BrowseCraft could not sign out. Try again.", comment: "")
                : NSLocalizedString("Sign in with Apple could not be completed. Try again.", comment: "")
            await self.refreshPortalAccountStatus()
        }
    }

    @MainActor
    func selectImageCacheLimit(_ limit: ImageCacheLimitOption) {
        let settings: ImageCacheSettings = ImageCacheSettings(limit: limit)

        do {
            try self.imageCacheManager.apply(settings: settings)
            self.imageCacheManager.trimConfiguredDataCacheIfNeeded(settings: settings)
            self.imageCacheSettings = settings
            self.cacheErrorMessage = nil
            AppAnalytics.shared.logSettingChanged(
                name: "image_cache_limit",
                value: String(limit.megabytes)
            )
        } catch {
            AppLog.error(
                .cache,
                event: "image-cache-settings-update-failed",
                metadata: ["error": AppLog.safeErrorCode(error)]
            )
            self.cacheErrorMessage = NSLocalizedString("Image cache settings could not be updated.", comment: "")
        }
    }

    /// 中文注释：缓存页出现、改上限、清除之后重算用量；磁盘读取在缓存自己的队列上，不占主线程。
    @MainActor
    func refreshImageCacheUsage() async {
        self.imageCacheUsage = await self.imageCacheManager.usage()
    }

    /// 中文注释：不弹确认（用户裁定），等磁盘真正清完后重算用量，并显示释放了多少（只算图片部分，网页缓存大小拿不到）。
    @MainActor
    func clearImageCache() async {
        guard self.isClearingCache == false else {
            return
        }
        self.isClearingCache = true
        self.cacheErrorMessage = nil
        let before: ImageCacheUsage
        if let usage: ImageCacheUsage = self.imageCacheUsage {
            before = usage
        } else {
            before = await self.imageCacheManager.usage()
        }

        await self.imageCacheManager.clearAllCaches()
        let after: ImageCacheUsage = await self.imageCacheManager.usage()
        self.imageCacheUsage = after
        self.isClearingCache = false

        let freedBytes: Int = max(0, before.totalBytes - after.totalBytes)
        self.clearResultToken += 1
        let token: Int = self.clearResultToken
        self.lastClearedBytes = freedBytes
        AppLog.notice(.cache, event: "image-cache-cleared", metadata: ["freedBytes": String(freedBytes)])

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, self.clearResultToken == token else {
                return
            }
            self.lastClearedBytes = nil
        }
    }

    @MainActor
    func authorizeUserInitiatedStoreKitAction() async throws -> UUID {
        return try await self.purchaseCoordinator.authorizeUserInitiatedAction()
    }

    @MainActor
    func validateAuthorizedStoreKitUser(_ userID: UUID) async throws {
        try await self.purchaseCoordinator.validateAuthorizedUser(userID)
    }

    @MainActor
    func submitStoreKitPurchase(
        transaction: StoreKit.Transaction,
        signedTransaction: String,
        plan: InAppPurchasePlan
    ) async throws -> Set<String> {
        let environment: PortalPurchaseEnvironment =
            try StoreKitPortalEnvironmentMapper.map(transaction.environment)
        return try await self.purchaseCoordinator.submitPurchase(
            transaction: self.snapshot(transaction: transaction, environment: environment),
            signedTransaction: signedTransaction,
            expectedProductID: plan.productID
        )
    }

    @MainActor
    func processStoreKitTransactionUpdate(
        transaction: StoreKit.Transaction,
        signedTransaction: String,
        plan: InAppPurchasePlan
    ) async throws -> Set<String> {
        let environment: PortalPurchaseEnvironment =
            try StoreKitPortalEnvironmentMapper.map(transaction.environment)
        return try await self.purchaseCoordinator.submitUpdate(
            transaction: self.snapshot(transaction: transaction, environment: environment),
            signedTransaction: signedTransaction,
            expectedProductID: plan.productID
        )
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
        try await self.purchaseCoordinator.validateAuthorizedUser(authorizedUserID)
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

        try await self.purchaseCoordinator.validateAuthorizedUser(authorizedUserID)
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

        let activeProductIDs: Set<String> = try await self.purchaseCoordinator.restore(
            userID: authorizedUserID,
            environment: environment,
            signedTransactions: restorableTransactions.map(\.signedTransaction),
            transactions: restorableTransactions.map { candidate in
                self.snapshot(
                    transaction: candidate.transaction,
                    environment: candidate.environment
                )
            }
        )
        for candidate: RestorableStoreKitTransaction in restorableTransactions {
            await candidate.transaction.finish()
        }
        IAPDiagnostics.notice(
            "event=restore-completed " +
                "environment=\(environment.rawValue) " +
                "transactionCount=\(restorableTransactions.count) " +
                "activeProductCount=\(activeProductIDs.count)"
        )
        return activeProductIDs
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

    private func snapshot(
        transaction: StoreKit.Transaction,
        environment: PortalPurchaseEnvironment
    ) -> StoreTransactionSnapshot {
        return StoreTransactionSnapshot(
            transactionID: String(transaction.id),
            originalTransactionID: String(transaction.originalID),
            productID: transaction.productID,
            productType: transaction.productType.rawValue,
            environment: environment,
            environmentRawValue: transaction.environment.rawValue,
            ownershipType: transaction.ownershipType.rawValue,
            appAccountToken: transaction.appAccountToken,
            purchaseDate: transaction.purchaseDate,
            expirationDate: transaction.expirationDate,
            revocationDate: transaction.revocationDate
        )
    }
}

private struct RestorableStoreKitTransaction {
    let transaction: StoreKit.Transaction
    let signedTransaction: String
    let plan: InAppPurchasePlan
    let environment: PortalPurchaseEnvironment
}
