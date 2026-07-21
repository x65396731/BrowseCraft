import StoreKit
import SwiftUI

struct InAppPurchaseSheetView: View {
    @StateObject private var store: InAppPurchaseStore
    private let animationAssets: PurchaseAnimationPlayerView.Assets
    private let closeAction: () -> Void

    init(
        applyPurchaseAction: @escaping @MainActor (StoreKit.Transaction, InAppPurchasePlan) async throws -> Void = { _, _ in },
        restorePurchasesAction: @escaping @MainActor () async throws -> Void = {
            try await AppStore.sync()
        },
        closeAction: @escaping () -> Void = {},
        animationResource: BundledPurchaseAnimationResource = BundledPurchaseAnimationResource()
    ) {
        self.animationAssets = PurchaseAnimationPlayerView.Assets(resource: animationResource)
        self.closeAction = closeAction
        _store = StateObject(
            wrappedValue: InAppPurchaseStore(
                applyPurchaseAction: applyPurchaseAction,
                restorePurchasesAction: restorePurchasesAction
            )
        )
    }

    var body: some View {
        ZStack {
            PurchaseAnimationPlayerView(
                assets: self.animationAssets,
                isPlaybackEnabled: self.store.status.suspendsBackgroundAnimation == false
            )

            InAppPurchasePlanSelectionView(
                store: self.store,
                closeAction: self.closeAction
            )
        }
        .preferredColorScheme(.dark)
    }
}
