import BrowseCraftLog
import Observation
import StoreKit
import SwiftUI

@MainActor
@Observable
final class InAppPurchaseStore {
    typealias Status = InAppPurchaseStatus

    private(set) var isLoading: Bool = false
    private(set) var hasLoadedProducts: Bool = false
    private(set) var activeProductID: String?
    private(set) var productsByID: [String: Product] = [:]
    private(set) var storeKitOwnedProductIDs: Set<String> = []
    private(set) var unverifiedStoreKitProductIDs: Set<String> = []
    private(set) var portalEntitledProductIDs: Set<String> = []
    /// 中文注释：StoreKit 拥有、但还没被当前账号认领的商品（删除账号设计第 9.2 节）；显示「需要恢复」。
    private(set) var unclaimedStoreKitProductIDs: Set<String> = []
    private(set) var status: Status = .idle {
        didSet {
            guard oldValue != self.status else {
                return
            }
            AppLog.notice(.purchase, "ui-status-changed", [
                "from": .code("\(oldValue.diagnosticCode)"),
                "to": .code("\(self.status.diagnosticCode)")
            ])
        }
    }

    private let authorizeStoreKitAction: @MainActor () async throws -> UUID
    private let validateAuthorizedUser: @MainActor (UUID) async throws -> Void
    private let applyPurchaseAction: @MainActor (
        StoreKit.Transaction,
        String,
        InAppPurchasePlan
    ) async throws -> Set<String>
    private let isTransactionClaimed: @MainActor (String, UUID?) async -> Bool
    private let restorePurchasesAction: @MainActor (
        UUID
    ) async throws -> Set<String>?

    init(
        authorizeStoreKitAction: @escaping @MainActor () async throws -> UUID = {
            throw StoreKitPurchaseIdentityAuthorizationError.signInRequired
        },
        validateAuthorizedUser: @escaping @MainActor (UUID) async throws -> Void = { _ in
            throw StoreKitPurchaseIdentityAuthorizationError.activeUserChanged
        },
        applyPurchaseAction: @escaping @MainActor (
            StoreKit.Transaction,
            String,
            InAppPurchasePlan
        ) async throws -> Set<String> = { _, _, _ in
            throw StoreKitPortalPurchaseSubmissionError
                .snapshotContractMismatch
        },
        restorePurchasesAction: @escaping @MainActor (
            UUID
        ) async throws -> Set<String>? = { _ in
            try await AppStore.sync()
            return nil
        },
        isTransactionClaimed: @escaping @MainActor (String, UUID?) async -> Bool = { _, _ in true }
    ) {
        self.authorizeStoreKitAction = authorizeStoreKitAction
        self.validateAuthorizedUser = validateAuthorizedUser
        self.applyPurchaseAction = applyPurchaseAction
        self.restorePurchasesAction = restorePurchasesAction
        self.isTransactionClaimed = isTransactionClaimed
    }

    func loadProducts() async {
        guard self.isLoading == false else {
            return
        }

        let shouldLoadProducts: Bool = self.hasLoadedProducts == false
        self.isLoading = true
        if shouldLoadProducts {
            AppLog.notice(.purchase, "product-load-started")
            self.status = .loadingProducts
        }
        defer {
            self.isLoading = false
            if shouldLoadProducts {
                self.hasLoadedProducts = true
            }
        }

        await self.refreshStoreKitOwnedProductIDs()
        guard Task.isCancelled == false,
              shouldLoadProducts else {
            return
        }

        do {
            let activePlans: [InAppPurchasePlan] = InAppPurchasePlan.activePlans
            let products: [Product] = try await Product.products(
                for: activePlans.map(\.productID)
            )
            self.productsByID = Dictionary(uniqueKeysWithValues: products.map { product in
                return (product.id, product)
            })
            let requestedProductIDs: Set<String> = Set(
                activePlans.map(\.productID)
            )
            let receivedProductIDs: Set<String> = Set(
                products.map(\.id)
            )
            let missingProductIDs: Set<String> = requestedProductIDs
                .subtracting(receivedProductIDs)
            AppLog.notice(.purchase, "product-load-completed", [
                "requestedCount": .int(activePlans.count),
                "receivedCount": .int(products.count),
                "receivedProductIDs": .code("\(receivedProductIDs.sorted())"),
                "missingProductIDs": .code("\(missingProductIDs.sorted())")
            ])

            if products.isEmpty {
                self.status = .productsUnavailable
                AppAnalytics.shared.logPaywallProductsLoaded(.unavailable)
            } else if products.count < activePlans.count {
                self.status = .someProductsUnavailable
                AppAnalytics.shared.logPaywallProductsLoaded(.partial)
            } else {
                self.status = .idle
                AppAnalytics.shared.logPaywallProductsLoaded(.available)
            }
        } catch is CancellationError {
            AppLog.notice(.purchase, "product-load-cancelled")
            return
        } catch {
            AppLog.error(.purchase, "product-load-failed", ["error": .code(IAPDiagnostics.safeErrorCode(error))])
            self.status = .productLoadFailed
            AppAnalytics.shared.logPaywallProductsLoaded(.failed)
        }
    }

    func priceText(for plan: InAppPurchasePlan) -> String? {
        return self.productsByID[plan.productID]?.displayPrice
    }

    func isPurchasePending(_ plan: InAppPurchasePlan) -> Bool {
        guard case .pending(let productID, _) = self.status else {
            return false
        }

        return productID == plan.productID
    }

    func purchase(_ plan: InAppPurchasePlan) async {
        var hasVerifiedStoreKitPurchase: Bool = false
        AppLog.notice(.purchase, "purchase-button-tapped", ["productID": .code("\(plan.productID)")])

        guard InAppPurchasePlan.activePlans.contains(where: { activePlan in
            return activePlan.productID == plan.productID
        }) else {
            self.status = .productUnavailable(title: plan.title)
            return
        }

        guard self.activeProductID == nil,
              self.isPurchasePending(plan) == false else {
            return
        }

        self.activeProductID = plan.productID
        defer {
            self.activeProductID = nil
        }
        // 中文注释：App Store 账户已买过、被预检挡下时，`transactionIdentityMismatch` 也算 already_owned。
        var isBlockedAsAlreadyOwned: Bool = false
        defer {
            Self.logPurchaseResult(
                productID: plan.productID,
                status: self.status,
                isBlockedAsAlreadyOwned: isBlockedAsAlreadyOwned
            )
        }

        if self.hasLoadedProducts == false {
            await self.loadProducts()
        }

        guard let product: Product = self.productsByID[plan.productID] else {
            self.status = .productUnavailable(title: plan.title)
            return
        }

        do {
            self.status = .checkingIdentity
            let authorizedUserID: UUID = try await self.authorizeStoreKitAction()
            try Task.checkCancellation()

            let purchaseEligibility: PurchaseEligibility =
                try await self.purchaseEligibility(
                    for: plan
                )
            switch purchaseEligibility {
            case .purchasable:
                break
            case .owned(let appAccountToken):
                AppLog.notice(.purchase, "purchase-preflight-blocked", [
                    "reason": .code("already-owned"),
                    "productID": .code("\(plan.productID)")
                ])
                // 中文注释：这个 App Store 账户已经买过：不论记在哪个账号名下都引导去「恢复购买」——
                // 原账号已删除时恢复会把它认领到当前账号（docs/design/Account-Deletion-Design.md 第 9.2 节）。
                isBlockedAsAlreadyOwned = true
                self.status = appAccountToken == nil
                    ? .transactionIdentityMismatch(title: plan.title)
                    : .alreadyPurchased(title: plan.title)
                return
            case .unverified:
                AppLog.error(.purchase, "purchase-preflight-blocked", [
                    "reason": .code("unverified"),
                    "productID": .code("\(plan.productID)")
                ])
                self.status = .unverified(title: plan.title)
                return
            }

            self.status = .purchasing(productID: plan.productID, title: plan.title)
            AppAnalytics.shared.logPurchaseStarted(productID: plan.productID)
            let result: Product.PurchaseResult = try await product.purchase(
                options: [.appAccountToken(authorizedUserID)]
            )
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    hasVerifiedStoreKitPurchase = true
                    AppLog.notice(.purchase, "storekit-transaction-verified", [
                        "transactionHash": .id(String(transaction.id)),
                        "productID": .code("\(transaction.productID)"),
                        "environment": .enumValue(transaction.environment),
                        "hasAppAccountToken": .bool(transaction.appAccountToken != nil)
                    ])

                    if transaction.revocationDate != nil {
                        await transaction.finish()
                        self.storeKitOwnedProductIDs.remove(plan.productID)
                        self.unverifiedStoreKitProductIDs.remove(plan.productID)
                        self.portalEntitledProductIDs.remove(plan.productID)
                        self.status = .revoked(title: plan.title)
                        return
                    }

                    self.storeKitOwnedProductIDs.insert(plan.productID)
                    self.unverifiedStoreKitProductIDs.remove(plan.productID)
                    // 中文注释：外来 token（非消耗型重买时 App Store 交回原交易）不在本地拦截，交服务端判定（第 9.2 节）。
                    guard transaction.appAccountToken != nil else {
                        self.status = .transactionIdentityMismatch(title: plan.title)
                        return
                    }
                    try await self.validateAuthorizedUser(authorizedUserID)

                    self.status = .submittingPurchase(
                        productID: plan.productID,
                        title: plan.title
                    )
                    let activeProductIDs: Set<String> =
                        try await self.applyPurchaseAction(
                            transaction,
                            verification.jwsRepresentation,
                            plan
                        )
                    await transaction.finish()
                    AppLog.notice(.purchase, "storekit-transaction-finished", [
                        "transactionHash": .id(String(transaction.id))
                    ])
                    self.portalEntitledProductIDs = Self.portalEntitledProductIDs(
                        from: activeProductIDs
                    )
                    self.status = .purchased(title: plan.title)
                case .unverified:
                    AppLog.error(.purchase, "storekit-purchase-failed", ["reason": .code("unverified")])
                    self.unverifiedStoreKitProductIDs.insert(plan.productID)
                    self.status = .unverified(title: plan.title)
                }
            case .pending:
                AppLog.notice(.purchase, "storekit-purchase-pending", ["productID": .code("\(plan.productID)")])
                self.status = .pending(productID: plan.productID, title: plan.title)
            case .userCancelled:
                AppLog.notice(.purchase, "storekit-purchase-cancelled", ["productID": .code("\(plan.productID)")])
                self.status = .cancelled
            @unknown default:
                AppLog.error(.purchase, "storekit-purchase-failed", ["reason": .code("unknown-result")])
                self.status = .purchaseFailed(title: plan.title)
            }
        } catch let error as CancellationError {
            AppLog.error(.purchase, "purchase-flow-failed", [
                "error": .code(IAPDiagnostics.safeErrorCode(error)),
                "storeKitVerified": .bool(hasVerifiedStoreKitPurchase)
            ])
            self.status = hasVerifiedStoreKitPurchase
                ? .portalSubmissionInterrupted(title: plan.title)
                : .cancelled
        } catch let error as StoreKitPurchaseIdentityAuthorizationError {
            Self.logFailure(error, flow: "purchase")
            self.status = Self.status(for: error)
        } catch let error as StoreKitTransactionIdentityError {
            Self.logFailure(error, flow: "purchase")
            self.status = .transactionIdentityMismatch(title: plan.title)
        } catch let error as StoreKitPortalPurchaseSubmissionError {
            Self.logFailure(error, flow: "purchase")
            self.status = Self.status(for: error, title: plan.title)
        } catch let error as PortalPurchaseEntitlementRefreshError {
            Self.logFailure(error, flow: "purchase")
            self.status = Self.status(for: error, title: plan.title)
        } catch let error as PortalIAPServiceError {
            Self.logFailure(error, flow: "purchase")
            self.status = Self.status(for: error, title: plan.title)
        } catch {
            Self.logFailure(error, flow: "purchase")
            self.status = hasVerifiedStoreKitPurchase
                ? .portalOutcomeUnknown(title: plan.title)
                : .purchaseFailed(title: plan.title)
        }
    }

    func restorePurchases() async {
        guard self.isLoading == false,
              self.activeProductID == nil else {
            return
        }

        AppLog.notice(.purchase, "restore-button-tapped")
        self.isLoading = true
        defer {
            self.isLoading = false
        }
        // 中文注释：恢复动作交回 nil 表示没有可恢复的交易（`restore-completed outcome=no-restorable-transactions`）。
        var hasNothingToRestore: Bool = false
        var isRestoreCancelled: Bool = false
        defer {
            if isRestoreCancelled == false {
                Self.logRestoreResult(status: self.status, hasNothingToRestore: hasNothingToRestore)
            }
        }

        do {
            self.status = .checkingIdentity
            let authorizedUserID: UUID = try await self.authorizeStoreKitAction()
            try Task.checkCancellation()

            self.status = .restoring
            let activeProductIDs: Set<String>? =
                try await self.restorePurchasesAction(authorizedUserID)
            hasNothingToRestore = activeProductIDs == nil
            try await self.validateAuthorizedUser(authorizedUserID)
            if let activeProductIDs {
                self.portalEntitledProductIDs =
                    Self.portalEntitledProductIDs(
                        from: activeProductIDs
                    )
            }

            let hasIdentityMismatch: Bool =
                await self.refreshStoreKitOwnedProductIDs(
                    ownedBy: authorizedUserID
                )
            try Task.checkCancellation()
            let revokedPlan: InAppPurchasePlan? =
                await self.latestRevokedPlan(ownedBy: authorizedUserID)
            if hasIdentityMismatch {
                self.status = .restoreAccountMismatch
            } else if let revokedPlan {
                self.status = .revoked(title: revokedPlan.title)
            } else {
                self.status = .restored
            }
        } catch let error as CancellationError {
            Self.logFailure(error, flow: "restore")
            isRestoreCancelled = true
            return
        } catch let error as StoreKitPurchaseIdentityAuthorizationError {
            Self.logFailure(error, flow: "restore")
            await self.refreshStoreKitOwnedProductIDs()
            self.status = Self.status(for: error)
        } catch let error as StoreKitTransactionIdentityError {
            Self.logFailure(error, flow: "restore")
            await self.refreshStoreKitOwnedProductIDs()
            self.status = .restoreAccountMismatch
        } catch let error as StoreKitPortalPurchaseSubmissionError {
            Self.logFailure(error, flow: "restore")
            await self.refreshStoreKitOwnedProductIDs()
            self.status = Self.status(
                for: error,
                title: NSLocalizedString("Restore Purchases", comment: "")
            )
        } catch let error as PortalPurchaseEntitlementRefreshError {
            Self.logFailure(error, flow: "restore")
            await self.refreshStoreKitOwnedProductIDs()
            self.status = Self.status(
                for: error,
                title: NSLocalizedString("Restore Purchases", comment: "")
            )
        } catch let error as PortalIAPServiceError {
            Self.logFailure(error, flow: "restore")
            await self.refreshStoreKitOwnedProductIDs()
            self.status = Self.status(
                for: error,
                title: NSLocalizedString("Restore Purchases", comment: "")
            )
        } catch {
            Self.logFailure(error, flow: "restore")
            await self.refreshStoreKitOwnedProductIDs()
            self.status = .restoreFailed
        }
    }

    /// 中文注释：已被当前账号认领的拥有才算「已购买」；未认领的走 `needsRestoreToClaim`。
    func isPurchased(_ plan: InAppPurchasePlan) -> Bool {
        return plan.productKind == .nonConsumable
            && self.storeKitOwnedProductIDs.contains(plan.productID)
            && self.needsRestoreToClaim(plan) == false
    }

    /// 中文注释：这个 App Store 账户买过、但当前账号还没认领——点「恢复购买」认领（删除账号设计第 9.2 节）。
    func needsRestoreToClaim(_ plan: InAppPurchasePlan) -> Bool {
        return plan.productKind == .nonConsumable
            && self.storeKitOwnedProductIDs.contains(plan.productID)
            && self.unclaimedStoreKitProductIDs.contains(plan.productID)
            && self.portalEntitledProductIDs.contains(plan.productID) == false
    }

    func hasPortalEntitlement(_ plan: InAppPurchasePlan) -> Bool {
        return plan.productKind == .nonConsumable
            && self.portalEntitledProductIDs.contains(plan.productID)
    }

    func hasUnverifiedEntitlement(_ plan: InAppPurchasePlan) -> Bool {
        return plan.productKind == .nonConsumable
            && self.unverifiedStoreKitProductIDs.contains(plan.productID)
    }

    #if DEBUG
    func refundableSandboxTransactionID(
        for targetPlan: InAppPurchasePlan
    ) async throws -> StoreKit.Transaction.ID? {
        AppLog.notice(.purchase, "refund-test-transaction-search-started", [
            "productID": .code("\(targetPlan.productID)")
        ])
        let authorizedUserID: UUID = try await self.authorizeStoreKitAction()

        for await verification in StoreKit.Transaction.currentEntitlements {
            try Task.checkCancellation()
            guard case .verified(let transaction) = verification,
                  transaction.productID == targetPlan.productID,
                  transaction.environment == .sandbox,
                  transaction.revocationDate == nil,
                  transaction.appAccountToken == authorizedUserID else {
                continue
            }

            AppLog.notice(.purchase, "refund-test-transaction-search-completed", [
                "productID": .code("\(targetPlan.productID)"),
                "found": .code("true"),
                "transactionHash": .id(String(transaction.id))
            ])
            return transaction.id
        }

        AppLog.notice(.purchase, "refund-test-transaction-search-completed", [
            "productID": .code("\(targetPlan.productID)"),
            "found": .code("false")
        ])
        return nil
    }
    #endif

    func refreshAfterTransactionUpdate(
        activeProductIDs: Set<String>?
    ) async {
        let previouslyOwnedProductIDs: Set<String> =
            self.storeKitOwnedProductIDs
        if let activeProductIDs {
            self.portalEntitledProductIDs =
                Self.portalEntitledProductIDs(
                    from: activeProductIDs
                )
        }

        await self.refreshStoreKitOwnedProductIDs()

        if case .pending(let productID, let title) = self.status,
           self.storeKitOwnedProductIDs.contains(productID) {
            self.status = .alreadyPurchased(title: title)
            return
        }

        guard self.status.isInProgress == false,
              let revokedProductID: String =
                previouslyOwnedProductIDs
                    .subtracting(self.storeKitOwnedProductIDs)
                    .first,
              let revokedPlan: InAppPurchasePlan =
                InAppPurchasePlan.plansByProductID[revokedProductID] else {
            return
        }

        self.status = .revoked(title: revokedPlan.title)
    }

    @discardableResult
    private func refreshStoreKitOwnedProductIDs(
        ownedBy userID: UUID? = nil
    ) async -> Bool {
        AppLog.notice(.purchase, "storekit-entitlements-refresh-started")
        var ownedProductIDs: Set<String> = []
        var unverifiedProductIDs: Set<String> = []
        var unclaimedProductIDs: Set<String> = []
        var hasIdentityMismatch: Bool = false

        for await verification in StoreKit.Transaction.currentEntitlements {
            guard Task.isCancelled == false else {
                AppLog.notice(.purchase, "storekit-entitlements-refresh-cancelled")
                return false
            }

            switch verification {
            case .verified(let transaction):
                guard transaction.revocationDate == nil,
                      let plan: InAppPurchasePlan =
                        InAppPurchasePlan.plansByProductID[transaction.productID],
                      plan.isRestorable,
                      plan.productKind == .nonConsumable else {
                    continue
                }

                // 中文注释：外来 token 的购买已被当前账号认领（服务端权益里有它）就不算别人的（第 9.1 节）。
                if let userID,
                   transaction.appAccountToken != userID,
                   self.portalEntitledProductIDs.contains(transaction.productID) == false {
                    hasIdentityMismatch = true
                }
                ownedProductIDs.insert(transaction.productID)
                if await self.isTransactionClaimed(String(transaction.id), transaction.appAccountToken) == false {
                    unclaimedProductIDs.insert(transaction.productID)
                }
            case .unverified(let transaction, _):
                guard let plan: InAppPurchasePlan =
                        InAppPurchasePlan.plansByProductID[transaction.productID],
                      plan.isRestorable,
                      plan.productKind == .nonConsumable else {
                    continue
                }

                unverifiedProductIDs.insert(transaction.productID)
            }
        }

        guard Task.isCancelled == false else {
            AppLog.notice(.purchase, "storekit-entitlements-refresh-cancelled")
            return false
        }

        unverifiedProductIDs.subtract(ownedProductIDs)
        self.storeKitOwnedProductIDs = ownedProductIDs
        self.unverifiedStoreKitProductIDs = unverifiedProductIDs
        self.unclaimedStoreKitProductIDs = unclaimedProductIDs
        AppLog.notice(.purchase, "storekit-entitlements-refresh-completed", [
            "ownedCount": .int(ownedProductIDs.count),
            "unclaimedCount": .int(unclaimedProductIDs.count),
            "unverifiedCount": .int(unverifiedProductIDs.count),
            "hasIdentityMismatch": .bool(hasIdentityMismatch)
        ])
        return hasIdentityMismatch
    }

    private enum PurchaseEligibility {
        case purchasable
        case owned(appAccountToken: UUID?)
        case unverified
    }

    private func purchaseEligibility(
        for targetPlan: InAppPurchasePlan
    ) async throws -> PurchaseEligibility {
        var ownedProductIDs: Set<String> = []
        var unverifiedProductIDs: Set<String> = []
        var unclaimedProductIDs: Set<String> = []
        var targetTransaction: StoreKit.Transaction?

        for await verification in StoreKit.Transaction.currentEntitlements {
            try Task.checkCancellation()

            switch verification {
            case .verified(let transaction):
                guard transaction.revocationDate == nil,
                      let plan: InAppPurchasePlan =
                        InAppPurchasePlan.plansByProductID[transaction.productID],
                      plan.productKind == .nonConsumable else {
                    continue
                }

                ownedProductIDs.insert(transaction.productID)
                if await self.isTransactionClaimed(String(transaction.id), transaction.appAccountToken) == false {
                    unclaimedProductIDs.insert(transaction.productID)
                }
                if transaction.productID == targetPlan.productID {
                    targetTransaction = transaction
                }
            case .unverified(let transaction, _):
                guard let plan: InAppPurchasePlan =
                        InAppPurchasePlan.plansByProductID[transaction.productID],
                      plan.productKind == .nonConsumable else {
                    continue
                }

                unverifiedProductIDs.insert(transaction.productID)
            }
        }

        try Task.checkCancellation()
        unverifiedProductIDs.subtract(ownedProductIDs)
        self.storeKitOwnedProductIDs = ownedProductIDs
        self.unverifiedStoreKitProductIDs = unverifiedProductIDs
        self.unclaimedStoreKitProductIDs = unclaimedProductIDs

        if let targetTransaction {
            return .owned(
                appAccountToken: targetTransaction.appAccountToken
            )
        }
        if unverifiedProductIDs.contains(targetPlan.productID) {
            return .unverified
        }
        return .purchasable
    }

    private func latestRevokedPlan(ownedBy userID: UUID) async -> InAppPurchasePlan? {
        for plan in InAppPurchasePlan.activePlans {
            guard let verification: VerificationResult<StoreKit.Transaction> = await StoreKit.Transaction.latest(
                for: plan.productID
            ),
                  case .verified(let transaction) = verification,
                  transaction.appAccountToken == userID,
                  transaction.revocationDate != nil else {
                continue
            }

            return plan
        }

        return nil
    }

    private static func status(
        for error: StoreKitPurchaseIdentityAuthorizationError
    ) -> Status {
        switch error {
        case .signInRequired:
            return .portalSignInRequired
        case .activeUserChanged:
            return .identityMismatch
        }
    }

    private static func status(
        for error: StoreKitPortalPurchaseSubmissionError,
        title: String
    ) -> Status {
        switch error {
        case .xcodeEnvironmentUnsupported:
            return .xcodeEnvironmentUnsupported(title: title)
        case .unsupportedEnvironment:
            return .storeKitEnvironmentUnsupported(title: title)
        case .transactionProductMismatch,
             .snapshotContractMismatch,
             .purchasedProductMissing:
            return .portalOutcomeUnknown(title: title)
        }
    }

    private static func status(
        for error: PortalPurchaseEntitlementRefreshError,
        title: String
    ) -> Status {
        switch error {
        case .activeUserChanged:
            return .identityCheckFailed
        case .sessionUnavailable:
            return .portalSessionUnavailable(title: title)
        case .snapshotMismatch:
            return .portalOutcomeUnknown(title: title)
        }
    }

    private static func status(
        for error: PortalIAPServiceError,
        title: String
    ) -> Status {
        switch error {
        case .temporarilyUnavailable, .rateLimited:
            return .portalTemporarilyUnavailable(title: title)
        case .responseOutcomeUnknown:
            return .portalOutcomeUnknown(title: title)
        case .sessionRejected:
            return .portalSessionUnavailable(title: title)
        case .subjectMismatch, .accountTokenMissing, .accountMismatch:
            return .portalAccountMismatch(title: title)
        case .transactionAlreadyClaimed:
            return .portalTransactionClaimed(title: title)
        case .unverifiedTransaction, .bundleMismatch,
             .environmentMismatch, .unknownProduct,
             .revokedTransaction, .invalidRequest,
             .contractRejected, .clientConfiguration:
            return .portalSubmissionRejected(title: title)
        }
    }

    private static func portalEntitledProductIDs(
        from activeProductIDs: Set<String>
    ) -> Set<String> {
        return Set(
            InAppPurchasePlan.activePlans.compactMap { plan in
                guard plan.productKind == .nonConsumable,
                      activeProductIDs.contains(plan.productID) else {
                    return nil
                }
                return plan.productID
            }
        )
    }

    // MARK: - 埋点

    /// 中文注释：一次购买走到终态后报 `purchase_result`；仍在进行中（被取消的任务等）不报。
    private static func logPurchaseResult(
        productID: String,
        status: Status,
        isBlockedAsAlreadyOwned: Bool
    ) {
        if isBlockedAsAlreadyOwned {
            AppAnalytics.shared.logPurchaseResult(productID: productID, result: .alreadyOwned)
            return
        }
        guard let result: PurchaseResult = status.purchaseAnalyticsResult else {
            return
        }
        AppAnalytics.shared.logPurchaseResult(
            productID: productID,
            result: result,
            errorCode: result == .failed ? status.analyticsFailureCode : nil
        )
    }

    private static func logRestoreResult(status: Status, hasNothingToRestore: Bool) {
        guard let result: RestoreResult = status.restoreAnalyticsResult else {
            return
        }
        if result == .success && hasNothingToRestore {
            AppAnalytics.shared.logRestoreResult(.nothingToRestore)
        } else {
            AppAnalytics.shared.logRestoreResult(result)
        }
    }

    private static func logFailure(_ error: any Error, flow: String) {
        AppLog.error(.purchase, "\(flow)-flow-failed", ["error": .code(IAPDiagnostics.safeErrorCode(error))])
    }
}
