import StoreKit
import SwiftUI

struct InAppPurchaseSheetView: View {
    @StateObject private var store: InAppPurchaseStore
    private let animationAssets: PurchaseAnimationPlayerView.Assets
    private let closeAction: () -> Void

    init(
        authorizeStoreKitAction: @escaping @MainActor () async throws -> UUID = {
            throw StoreKitPurchaseIdentityAuthorizationError.notAssociated
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
        restorePurchasesAction: @escaping @MainActor (UUID) async throws -> Void = { _ in
            try await AppStore.sync()
        },
        closeAction: @escaping () -> Void = {},
        animationResource: BundledPurchaseAnimationResource = BundledPurchaseAnimationResource()
    ) {
        self.animationAssets = PurchaseAnimationPlayerView.Assets(resource: animationResource)
        self.closeAction = closeAction
        _store = StateObject(
            wrappedValue: InAppPurchaseStore(
                authorizeStoreKitAction: authorizeStoreKitAction,
                validateAuthorizedUser: validateAuthorizedUser,
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
