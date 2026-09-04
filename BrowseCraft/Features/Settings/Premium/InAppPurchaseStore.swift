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
    private(set) var status: Status = .idle {
        didSet {
            guard oldValue != self.status else {
                return
            }
            IAPDiagnostics.notice(
                "event=ui-status-changed " +
                    "from=\(oldValue.diagnosticCode) " +
                    "to=\(self.status.diagnosticCode)"
            )
        }
    }

    private let authorizeStoreKitAction: @MainActor () async throws -> UUID
    private let validateAuthorizedUser: @MainActor (UUID) async throws -> Void
    private let applyPurchaseAction: @MainActor (
        StoreKit.Transaction,
        String,
        InAppPurchasePlan
    ) async throws -> Set<String>
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
        }
    ) {
        self.authorizeStoreKitAction = authorizeStoreKitAction
        self.validateAuthorizedUser = validateAuthorizedUser
        self.applyPurchaseAction = applyPurchaseAction
        self.restorePurchasesAction = restorePurchasesAction
    }

    func loadProducts() async {
        guard self.isLoading == false else {
            return
        }

        let shouldLoadProducts: Bool = self.hasLoadedProducts == false
        self.isLoading = true
        if shouldLoadProducts {
            IAPDiagnostics.notice("event=product-load-started")
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
            IAPDiagnostics.notice(
                "event=product-load-completed " +
                    "requestedCount=\(activePlans.count) " +
                    "receivedCount=\(products.count) " +
                    "receivedProductIDs=\(receivedProductIDs.sorted()) " +
                    "missingProductIDs=\(missingProductIDs.sorted())"
            )

            if products.isEmpty {
                self.status = .productsUnavailable
            } else if products.count < activePlans.count {
                self.status = .someProductsUnavailable
            } else {
                self.status = .idle
            }
        } catch is CancellationError {
            IAPDiagnostics.notice("event=product-load-cancelled")
            return
        } catch {
            IAPDiagnostics.error(
                "event=product-load-failed " +
                    "error=\(IAPDiagnostics.safeErrorCode(error))"
            )
            self.status = .productLoadFailed
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
        IAPDiagnostics.notice(
            "event=purchase-button-tapped productID=\(plan.productID)"
        )

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
                IAPDiagnostics.notice(
                    "event=purchase-preflight-blocked " +
                        "reason=already-owned productID=\(plan.productID)"
                )
                self.status = appAccountToken == authorizedUserID
                    ? .alreadyPurchased(title: plan.title)
                    : .transactionIdentityMismatch(title: plan.title)
                return
            case .unverified:
                IAPDiagnostics.error(
                    "event=purchase-preflight-blocked " +
                        "reason=unverified productID=\(plan.productID)"
                )
                self.status = .unverified(title: plan.title)
                return
            }

            self.status = .purchasing(productID: plan.productID, title: plan.title)
            let result: Product.PurchaseResult = try await product.purchase(
                options: [.appAccountToken(authorizedUserID)]
            )
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    hasVerifiedStoreKitPurchase = true
                    IAPDiagnostics.notice(
                        "event=storekit-transaction-verified " +
                            "transactionHash=\(IAPDiagnostics.hash(transactionID: transaction.id)) " +
                            "productID=\(transaction.productID) " +
                            "environment=\(transaction.environment.rawValue) " +
                            "hasAppAccountToken=\(transaction.appAccountToken != nil)"
                    )

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
                    guard transaction.appAccountToken == authorizedUserID else {
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
                    IAPDiagnostics.notice(
                        "event=storekit-transaction-finished " +
                            "transactionHash=\(IAPDiagnostics.hash(transactionID: transaction.id))"
                    )
                    self.portalEntitledProductIDs = Self.portalEntitledProductIDs(
                        from: activeProductIDs
                    )
                    self.status = .purchased(title: plan.title)
                case .unverified:
                    IAPDiagnostics.error(
                        "event=storekit-purchase-failed reason=unverified"
                    )
                    self.unverifiedStoreKitProductIDs.insert(plan.productID)
                    self.status = .unverified(title: plan.title)
                }
            case .pending:
                IAPDiagnostics.notice(
                    "event=storekit-purchase-pending productID=\(plan.productID)"
                )
                self.status = .pending(productID: plan.productID, title: plan.title)
            case .userCancelled:
                IAPDiagnostics.notice(
                    "event=storekit-purchase-cancelled productID=\(plan.productID)"
                )
                self.status = .cancelled
            @unknown default:
                IAPDiagnostics.error(
                    "event=storekit-purchase-failed reason=unknown-result"
                )
                self.status = .purchaseFailed(title: plan.title)
            }
        } catch let error as CancellationError {
            IAPDiagnostics.error(
                "event=purchase-flow-failed " +
                    "error=\(IAPDiagnostics.safeErrorCode(error)) " +
                    "storeKitVerified=\(hasVerifiedStoreKitPurchase)"
            )
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

        IAPDiagnostics.notice("event=restore-button-tapped")
        self.isLoading = true
        defer {
            self.isLoading = false
        }

        do {
            self.status = .checkingIdentity
            let authorizedUserID: UUID = try await self.authorizeStoreKitAction()
            try Task.checkCancellation()

            self.status = .restoring
            let activeProductIDs: Set<String>? =
                try await self.restorePurchasesAction(authorizedUserID)
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
                title: "Restore Purchases"
            )
        } catch let error as PortalPurchaseEntitlementRefreshError {
            Self.logFailure(error, flow: "restore")
            await self.refreshStoreKitOwnedProductIDs()
            self.status = Self.status(
                for: error,
                title: "Restore Purchases"
            )
        } catch let error as PortalIAPServiceError {
            Self.logFailure(error, flow: "restore")
            await self.refreshStoreKitOwnedProductIDs()
            self.status = Self.status(
                for: error,
                title: "Restore Purchases"
            )
        } catch {
            Self.logFailure(error, flow: "restore")
            await self.refreshStoreKitOwnedProductIDs()
            self.status = .restoreFailed
        }
    }

    func isPurchased(_ plan: InAppPurchasePlan) -> Bool {
        return plan.productKind == .nonConsumable
            && self.storeKitOwnedProductIDs.contains(plan.productID)
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
        IAPDiagnostics.notice(
            "event=refund-test-transaction-search-started " +
                "productID=\(targetPlan.productID)"
        )
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

            IAPDiagnostics.notice(
                "event=refund-test-transaction-search-completed " +
                    "productID=\(targetPlan.productID) found=true " +
                    "transactionHash=\(IAPDiagnostics.hash(transactionID: transaction.id))"
            )
            return transaction.id
        }

        IAPDiagnostics.notice(
            "event=refund-test-transaction-search-completed " +
                "productID=\(targetPlan.productID) found=false"
        )
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
        IAPDiagnostics.notice("event=storekit-entitlements-refresh-started")
        var ownedProductIDs: Set<String> = []
        var unverifiedProductIDs: Set<String> = []
        var hasIdentityMismatch: Bool = false

        for await verification in StoreKit.Transaction.currentEntitlements {
            guard Task.isCancelled == false else {
                IAPDiagnostics.notice(
                    "event=storekit-entitlements-refresh-cancelled"
                )
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

                if let userID,
                   transaction.appAccountToken != userID {
                    hasIdentityMismatch = true
                }
                ownedProductIDs.insert(transaction.productID)
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
            IAPDiagnostics.notice(
                "event=storekit-entitlements-refresh-cancelled"
            )
            return false
        }

        unverifiedProductIDs.subtract(ownedProductIDs)
        self.storeKitOwnedProductIDs = ownedProductIDs
        self.unverifiedStoreKitProductIDs = unverifiedProductIDs
        IAPDiagnostics.notice(
            "event=storekit-entitlements-refresh-completed " +
                "ownedCount=\(ownedProductIDs.count) " +
                "unverifiedCount=\(unverifiedProductIDs.count) " +
                "hasIdentityMismatch=\(hasIdentityMismatch)"
        )
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

    private static func logFailure(_ error: any Error, flow: String) {
        IAPDiagnostics.error(
            "event=\(flow)-flow-failed " +
                "error=\(IAPDiagnostics.safeErrorCode(error))"
        )
    }
}
