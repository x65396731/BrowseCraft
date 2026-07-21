import StoreKit
import SwiftUI

@MainActor
final class InAppPurchaseStore: ObservableObject {
    enum Status: Equatable {
        case idle
        case loadingProducts
        case productsUnavailable
        case someProductsUnavailable
        case productLoadFailed
        case productUnavailable(title: String)
        case purchasing(productID: String, title: String)
        case pending(productID: String, title: String)
        case cancelled
        case unverified(title: String)
        case purchaseFailed(title: String)
        case purchased(title: String)
        case restoring
        case restored
        case restoreFailed
        case revoked(title: String)

        var message: String? {
            switch self {
            case .idle:
                return nil
            case .loadingProducts:
                return "Loading StoreKit products…"
            case .productsUnavailable:
                return "No StoreKit products are currently available."
            case .someProductsUnavailable:
                return "Some StoreKit products are currently unavailable."
            case .productLoadFailed:
                return "StoreKit products could not be loaded."
            case .productUnavailable(let title):
                return "\(title) is not currently available for purchase."
            case .purchasing(_, let title):
                return "Purchasing \(title)…"
            case .pending(_, let title):
                return "\(title) is awaiting approval. No entitlement has been applied."
            case .cancelled:
                return "Purchase cancelled. No entitlement was applied."
            case .unverified(let title):
                return "\(title) could not be verified. No entitlement was applied."
            case .purchaseFailed(let title):
                return "\(title) could not be purchased."
            case .purchased(let title):
                return "\(title) purchase completed."
            case .restoring:
                return "Restoring purchases…"
            case .restored:
                return "Purchases restored."
            case .restoreFailed:
                return "Purchases could not be restored."
            case .revoked(let title):
                return "\(title) was revoked or refunded."
            }
        }

        var isInProgress: Bool {
            switch self {
            case .loadingProducts, .purchasing, .restoring:
                return true
            default:
                return false
            }
        }

        var suspendsBackgroundAnimation: Bool {
            switch self {
            case .purchasing, .restoring:
                return true
            default:
                return false
            }
        }
    }

    @Published private(set) var isLoading: Bool = false
    @Published private(set) var hasLoadedProducts: Bool = false
    @Published private(set) var activeProductID: String?
    @Published private(set) var productsByID: [String: Product] = [:]
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published private(set) var status: Status = .idle

    private let applyPurchaseAction: @MainActor (StoreKit.Transaction, InAppPurchasePlan) async throws -> Void
    private let restorePurchasesAction: @MainActor () async throws -> Void

    init(
        applyPurchaseAction: @escaping @MainActor (StoreKit.Transaction, InAppPurchasePlan) async throws -> Void = { _, _ in },
        restorePurchasesAction: @escaping @MainActor () async throws -> Void = {
            try await AppStore.sync()
        }
    ) {
        self.applyPurchaseAction = applyPurchaseAction
        self.restorePurchasesAction = restorePurchasesAction
    }

    func loadProducts() async {
        guard self.hasLoadedProducts == false else {
            return
        }

        self.isLoading = true
        self.status = .loadingProducts
        defer {
            self.isLoading = false
            self.hasLoadedProducts = true
        }

        do {
            let activePlans: [InAppPurchasePlan] = InAppPurchasePlan.activePlans
            let products: [Product] = try await Product.products(
                for: activePlans.map(\.productID)
            )
            self.productsByID = Dictionary(uniqueKeysWithValues: products.map { product in
                return (product.id, product)
            })

            let revokedPlan: InAppPurchasePlan? = await self.refreshPurchasedProductIDs()
            if let revokedPlan {
                self.status = .revoked(title: revokedPlan.title)
            } else if products.isEmpty {
                self.status = .productsUnavailable
            } else if products.count < activePlans.count {
                self.status = .someProductsUnavailable
            } else {
                self.status = .idle
            }
        } catch is CancellationError {
            return
        } catch {
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

        self.status = .purchasing(productID: plan.productID, title: plan.title)

        do {
            let result: Product.PurchaseResult = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    if transaction.revocationDate != nil {
                        await transaction.finish()
                        self.purchasedProductIDs.remove(plan.productID)
                        self.status = .revoked(title: plan.title)
                        return
                    }

                    try await self.applyPurchaseAction(transaction, plan)
                    await transaction.finish()
                    if plan.productKind == .nonConsumable {
                        self.purchasedProductIDs.insert(plan.productID)
                    }
                    self.status = .purchased(title: plan.title)
                case .unverified:
                    self.status = .unverified(title: plan.title)
                }
            case .pending:
                self.status = .pending(productID: plan.productID, title: plan.title)
            case .userCancelled:
                self.status = .cancelled
            @unknown default:
                self.status = .purchaseFailed(title: plan.title)
            }
        } catch is CancellationError {
            self.status = .cancelled
        } catch {
            self.status = .purchaseFailed(title: plan.title)
        }
    }

    func restorePurchases() async {
        guard self.isLoading == false,
              self.activeProductID == nil else {
            return
        }

        self.isLoading = true
        self.status = .restoring
        defer {
            self.isLoading = false
        }

        do {
            try await self.restorePurchasesAction()
            let revokedPlan: InAppPurchasePlan? = await self.refreshPurchasedProductIDs()
            if let revokedPlan {
                self.status = .revoked(title: revokedPlan.title)
            } else {
                self.status = .restored
            }
        } catch is CancellationError {
            return
        } catch {
            self.status = .restoreFailed
        }
    }

    func isPurchased(_ plan: InAppPurchasePlan) -> Bool {
        return plan.productKind == .nonConsumable
            && self.purchasedProductIDs.contains(plan.productID)
    }

    private func refreshPurchasedProductIDs() async -> InAppPurchasePlan? {
        var productIDs: Set<String> = []

        for await verification in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = verification,
                  let plan: InAppPurchasePlan = InAppPurchasePlan.plansByProductID[transaction.productID],
                  plan.productKind == .nonConsumable else {
                continue
            }

            if transaction.revocationDate != nil {
                continue
            }

            productIDs.insert(transaction.productID)
        }

        self.purchasedProductIDs = productIDs
        return await self.latestRevokedPlan()
    }

    private func latestRevokedPlan() async -> InAppPurchasePlan? {
        for plan in InAppPurchasePlan.activePlans {
            guard let verification: VerificationResult<StoreKit.Transaction> = await StoreKit.Transaction.latest(
                for: plan.productID
            ),
                  case .verified(let transaction) = verification,
                  transaction.revocationDate != nil else {
                continue
            }

            return plan
        }

        return nil
    }
}
