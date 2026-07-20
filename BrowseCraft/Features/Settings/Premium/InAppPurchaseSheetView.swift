import StoreKit
import SwiftUI

struct InAppPurchaseSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store: InAppPurchaseStore

    init(
        applyPurchaseAction: @escaping @MainActor (StoreKit.Transaction, InAppPurchasePlan) async throws -> Void = { _, _ in },
        restorePurchasesAction: @escaping @MainActor () async throws -> Void = {
            try await AppStore.sync()
        }
    ) {
        _store = StateObject(
            wrappedValue: InAppPurchaseStore(
                applyPurchaseAction: applyPurchaseAction,
                restorePurchasesAction: restorePurchasesAction
            )
        )
    }

    var body: some View {
        NavigationStack {
            InAppPurchasePlanSelectionView(
                store: self.store,
                closeAction: {
                    self.dismiss()
                }
            )
        }
        .alert("In-App Purchase", isPresented: self.store.statusAlertBinding) {
            Button("OK") {
                self.store.statusMessage = nil
            }
        } message: {
            Text(self.store.statusMessage ?? "")
        }
    }
}
