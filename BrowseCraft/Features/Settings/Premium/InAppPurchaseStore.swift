import StoreKit
import SwiftUI

@MainActor
final class InAppPurchaseStore: ObservableObject {
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var activeProductID: String?
    @Published private(set) var productsByID: [String: Product] = [:]
    @Published var statusMessage: String?

    private let applyPurchaseAction: @MainActor (StoreKit.Transaction, InAppPurchasePlan) async throws -> Void

    init(
        applyPurchaseAction: @escaping @MainActor (StoreKit.Transaction, InAppPurchasePlan) async throws -> Void = { _, _ in }
    ) {
        self.applyPurchaseAction = applyPurchaseAction
    }

    func loadProducts() async {
        guard self.productsByID.isEmpty else {
            return
        }

        self.isLoading = true
        self.statusMessage = nil
        defer {
            self.isLoading = false
        }

        do {
            let productIDs: [String] = InAppPurchasePlan.allPlans.map(\.productID)
            let products: [Product] = try await Product.products(for: productIDs)
            self.productsByID = Dictionary(uniqueKeysWithValues: products.map { product in
                return (product.id, product)
            })

            if products.isEmpty {
                self.statusMessage = "No StoreKit products were found. Add matching product IDs in a StoreKit configuration file for local testing."
            }
        } catch {
            self.statusMessage = "Products could not be loaded."
        }
    }

    func priceText(for plan: InAppPurchasePlan) -> String {
        return self.productsByID[plan.productID]?.displayPrice ?? plan.fallbackPrice
    }

    func purchase(_ plan: InAppPurchasePlan) async {
        guard self.activeProductID == nil else {
            return
        }

        self.activeProductID = plan.productID
        self.statusMessage = nil
        defer {
            self.activeProductID = nil
        }

        if self.productsByID.isEmpty {
            await self.loadProducts()
        }

        guard let product: Product = self.productsByID[plan.productID] else {
            self.statusMessage = "Product not available. Run the app from Xcode with the BrowseCraft scheme so BrowseCraft.storekit is injected."
            return
        }

        do {
            let result: Product.PurchaseResult = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction: StoreKit.Transaction = try self.verifiedTransaction(from: verification)
                try await self.applyPurchaseAction(transaction, plan)
                await transaction.finish()
                self.statusMessage = "\(plan.title) purchase completed."
            case .pending:
                self.statusMessage = "\(plan.title) purchase is pending."
            case .userCancelled:
                self.statusMessage = "Purchase cancelled."
            @unknown default:
                self.statusMessage = "Purchase ended with an unknown result."
            }
        } catch {
            self.statusMessage = "Purchase failed."
        }
    }

    func restorePurchases() async {
        self.isLoading = true
        self.statusMessage = nil
        defer {
            self.isLoading = false
        }

        do {
            try await AppStore.sync()
            self.statusMessage = "Purchases restored."
        } catch {
            self.statusMessage = "Purchases could not be restored."
        }
    }

    private func verifiedTransaction(
        from result: VerificationResult<StoreKit.Transaction>
    ) throws -> StoreKit.Transaction {
        switch result {
        case .verified(let transaction):
            return transaction
        case .unverified:
            throw StoreKitVerificationError.unverifiedTransaction
        }
    }

    var statusAlertBinding: Binding<Bool> {
        return Binding<Bool>(
            get: {
                return self.statusMessage != nil
            },
            set: { newValue in
                if newValue == false {
                    self.statusMessage = nil
                }
            }
        )
    }
}

private enum StoreKitVerificationError: Error {
    case unverifiedTransaction
}
