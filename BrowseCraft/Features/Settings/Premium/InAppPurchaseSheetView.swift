import StoreKit
import SwiftUI

struct InAppPurchaseSheetView: View {
    @State private var store: InAppPurchaseStore
    private let animationAssets: PurchaseAnimationPlayerView.Assets
    private let transactionUpdateRevision: UInt64
    private let transactionUpdateActiveProductIDs: Set<String>?
    private let closeAction: () -> Void

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
        transactionUpdateRevision: UInt64 = 0,
        transactionUpdateActiveProductIDs: Set<String>? = nil,
        closeAction: @escaping () -> Void = {},
        animationResource: BundledPurchaseAnimationResource = BundledPurchaseAnimationResource()
    ) {
        self.animationAssets = PurchaseAnimationPlayerView.Assets(resource: animationResource)
        self.transactionUpdateRevision = transactionUpdateRevision
        self.transactionUpdateActiveProductIDs =
            transactionUpdateActiveProductIDs
        self.closeAction = closeAction
        _store = State(
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
        .task(id: self.transactionUpdateRevision) {
            guard self.transactionUpdateRevision > 0 else {
                return
            }

            await self.store.refreshAfterTransactionUpdate(
                activeProductIDs:
                    self.transactionUpdateActiveProductIDs
            )
        }
    }
}
