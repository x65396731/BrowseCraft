import StoreKit
import SwiftUI

struct InAppPurchasePlanSelectionView: View {
    private struct PlanItem: Identifiable {
        let plan: InAppPurchasePlan
        let order: Int

        var id: String {
            return self.plan.id
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ObservedObject var store: InAppPurchaseStore
    let closeAction: () -> Void

    @State private var isDeckPresented: Bool = false
    @State private var selectedProductID: String?
    @State private var glowPhase: Bool = false
    @State private var purchaseTask: Task<Void, Never>?
    @State private var restoreTask: Task<Void, Never>?

    #if DEBUG
    @State private var refundPreparationTask: Task<Void, Never>?
    @State private var refundRequestTransactionID: StoreKit.Transaction.ID = 0
    @State private var isRefundRequestPresented: Bool = false
    @State private var refundTestMessage: String?
    #endif

    private let planItems: [PlanItem] = InAppPurchasePlan.activePlans.enumerated().map { index, plan in
        return PlanItem(plan: plan, order: index)
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    self.header

                    VStack(alignment: .leading, spacing: 6) {
                        Text("AVAILABLE UPGRADES")
                            .font(.caption.weight(.black))
                            .tracking(1.6)
                            .foregroundStyle(.white.opacity(0.72))

                        Text("Choose your power-up")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                    }

                    VStack(spacing: 14) {
                        ForEach(self.planItems) { item in
                            self.planButton(for: item)
                                .offset(
                                    y: self.isDeckPresented
                                        ? 0
                                        : self.deckTravelDistance(in: geometry)
                                )
                                .opacity(self.isDeckPresented ? 1 : 0)
                                .animation(
                                    self.deckAnimation(for: item.order),
                                    value: self.isDeckPresented
                                )
                        }
                    }

                    if let message: String = self.store.status.message {
                        HStack(alignment: .top, spacing: 10) {
                            if self.store.status.isInProgress {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: self.statusSystemImage)
                                    .foregroundStyle(self.statusColor)
                            }

                            Text(message)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.white.opacity(0.88))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Purchase status: \(message)")
                    }

                    Button(
                        action: {
                            self.restoreTask?.cancel()
                            self.restoreTask = Task {
                                await self.store.restorePurchases()
                                guard Task.isCancelled == false else {
                                    return
                                }
                                self.restoreTask = nil
                            }
                        },
                        label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.clockwise")
                                Text("Restore Purchases")
                            }
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(.ultraThinMaterial, in: Capsule())
                        }
                    )
                    .buttonStyle(.plain)
                    .disabled(self.interactionIsLocked)
                    .opacity(self.interactionIsLocked ? 0.55 : 1)
                    .accessibilityHint("Restores previously completed purchases")

                    #if DEBUG
                    self.refundTestControls
                    #endif
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        #if DEBUG
        .refundRequestSheet(
            for: self.refundRequestTransactionID,
            isPresented: self.$isRefundRequestPresented,
            onDismiss: self.handleRefundRequestResult
        )
        #endif
        .task {
            await self.presentDeckAndLoadProducts()
        }
        .onAppear {
            self.startGlowAnimationIfNeeded()
        }
        .onChange(of: self.reduceMotion) { _, shouldReduceMotion in
            if shouldReduceMotion {
                self.glowPhase = false
            } else {
                self.startGlowAnimationIfNeeded()
            }
        }
        .onDisappear {
            self.purchaseTask?.cancel()
            self.purchaseTask = nil
            self.restoreTask?.cancel()
            self.restoreTask = nil
            #if DEBUG
            self.refundPreparationTask?.cancel()
            self.refundPreparationTask = nil
            #endif
        }
    }

    #if DEBUG
    private var refundTestControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(
                action: {
                    self.refundPreparationTask?.cancel()
                    self.refundPreparationTask = Task {
                        await self.prepareRemoveAdsRefundRequest()
                    }
                },
                label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.uturn.backward.circle")
                        Text("Request Remove Ads Refund (DEBUG)")
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(.ultraThinMaterial, in: Capsule())
                }
            )
            .buttonStyle(.plain)
            .disabled(
                self.interactionIsLocked ||
                self.store.isPurchased(.removeAds) == false
            )
            .opacity(
                self.interactionIsLocked ||
                self.store.isPurchased(.removeAds) == false
                    ? 0.55
                    : 1
            )
            .accessibilityHint(
                "Opens Apple's refund request sheet for the verified Sandbox Remove Ads transaction"
            )

            if let refundTestMessage: String = self.refundTestMessage {
                Text(refundTestMessage)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @MainActor
    private func prepareRemoveAdsRefundRequest() async {
        defer {
            self.refundPreparationTask = nil
        }
        self.refundTestMessage = nil

        do {
            let transactionID: StoreKit.Transaction.ID? =
                try await self.store.refundableSandboxTransactionID(
                    for: .removeAds
                )
            try Task.checkCancellation()
            guard let transactionID else {
                self.refundTestMessage =
                    "No verified, active Sandbox Remove Ads transaction belongs to this BrowseCraft profile."
                return
            }

            self.refundRequestTransactionID = transactionID
            self.isRefundRequestPresented = true
        } catch is CancellationError {
            return
        } catch let error as StoreKitPurchaseIdentityAuthorizationError {
            IAPDiagnostics.error(
                "event=refund-test-preparation-failed " +
                    "error=\(IAPDiagnostics.safeErrorCode(error))"
            )
            self.refundTestMessage =
                "Link and verify the current iCloud identity before requesting a refund."
        } catch {
            IAPDiagnostics.error(
                "event=refund-test-preparation-failed " +
                    "error=\(IAPDiagnostics.safeErrorCode(error))"
            )
            self.refundTestMessage =
                "The Sandbox refund request could not be prepared."
        }
    }

    @MainActor
    private func handleRefundRequestResult(
        _ result: Result<
            StoreKit.Transaction.RefundRequestStatus,
            StoreKit.Transaction.RefundRequestError
        >
    ) {
        switch result {
        case .success(.success):
            IAPDiagnostics.notice(
                "event=refund-test-request-submitted productID=\(InAppPurchasePlan.removeAds.productID)"
            )
            self.refundTestMessage =
                "Apple received the refund request. Approval and entitlement revocation are still pending."
        case .success(.userCancelled):
            IAPDiagnostics.notice(
                "event=refund-test-request-cancelled productID=\(InAppPurchasePlan.removeAds.productID)"
            )
            self.refundTestMessage = "Refund request cancelled."
        case .failure(let error):
            IAPDiagnostics.error(
                "event=refund-test-request-failed " +
                    "error=\(IAPDiagnostics.safeErrorCode(error))"
            )
            self.refundTestMessage =
                "Apple could not present or submit the refund request."
        @unknown default:
            IAPDiagnostics.error(
                "event=refund-test-request-failed reason=unknown-status"
            )
            self.refundTestMessage =
                "The refund request returned an unknown status."
        }
    }
    #endif

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("啊？哥们你真买啊")
                    .font(.largeTitle.weight(.black))
                    .foregroundStyle(.white)

                Text("Permanent upgrades for your BrowseCraft loadout")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.72))
            }

            Spacer(minLength: 8)

            Button(action: self.closeAction) {
                Image(systemName: "xmark")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(self.interactionIsLocked)
            .opacity(self.interactionIsLocked ? 0.55 : 1)
            .accessibilityLabel("Close")
            .accessibilityHint(
                self.interactionIsLocked
                    ? "Available after the current StoreKit operation finishes"
                    : "Closes the purchase screen"
            )
        }
    }

    private var interactionIsLocked: Bool {
        return self.selectedProductID != nil
            || self.store.isLoading
            || self.store.activeProductID != nil
    }

    private func planButton(for item: PlanItem) -> some View {
        let plan: InAppPurchasePlan = item.plan
        let state: InAppPurchasePlanButton.State = self.planButtonState(for: plan)
        let isSelected: Bool = self.selectedProductID == plan.productID

        return Button(
            action: {
                self.purchaseTask?.cancel()
                self.purchaseTask = Task {
                    await self.presentStoreKitPurchase(for: plan)
                }
            },
            label: {
                InAppPurchasePlanButton(
                    plan: plan,
                    state: state,
                    isSelected: isSelected,
                    glowPhase: self.glowPhase
                )
            }
        )
        .buttonStyle(.plain)
        .disabled(self.interactionIsLocked || state.isPurchasable == false)
        .opacity(state.isPurchasable || isSelected ? 1 : 0.72)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(plan.title)
        .accessibilityValue(state.accessibilityValue)
        .accessibilityHint(state.isPurchasable ? "Double tap to purchase" : state.accessibilityValue)
    }

    private func planButtonState(for plan: InAppPurchasePlan) -> InAppPurchasePlanButton.State {
        if self.store.activeProductID == plan.productID {
            return .purchasing
        }

        if self.store.isPurchasePending(plan) {
            return .pending
        }

        if self.store.isPurchased(plan) {
            return .purchased
        }

        if self.store.hasUnverifiedEntitlement(plan) {
            return .verificationRequired
        }

        if let displayPrice: String = self.store.priceText(for: plan) {
            return .available(price: displayPrice)
        }

        if self.store.hasLoadedProducts {
            return .unavailable
        }

        return .loading
    }

    private var statusSystemImage: String {
        switch self.store.status {
        case .alreadyPurchased, .purchased, .restored:
            return "checkmark.circle.fill"
        case .pending:
            return "clock.badge.exclamationmark.fill"
        case .cancelled:
            return "xmark.circle.fill"
        case .idle, .loadingProducts, .checkingIdentity, .purchasing,
             .submittingPurchase, .restoring:
            return "hourglass"
        case .productsUnavailable,
             .someProductsUnavailable,
             .productLoadFailed,
             .productUnavailable,
             .portalSignInRequired,
             .identityMismatch,
             .identityCheckFailed,
             .restoreAccountMismatch,
             .unverified,
             .purchaseFailed,
             .transactionIdentityMismatch,
             .xcodeEnvironmentUnsupported,
             .storeKitEnvironmentUnsupported,
             .portalSessionUnavailable,
             .portalTemporarilyUnavailable,
             .portalAccountMismatch,
             .portalTransactionClaimed,
             .portalSubmissionRejected,
             .portalOutcomeUnknown,
             .portalSubmissionInterrupted,
             .restoreFailed,
             .revoked:
            return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch self.store.status {
        case .alreadyPurchased, .purchased, .restored:
            return .green
        case .pending:
            return .yellow
        case .cancelled:
            return .secondary
        default:
            return .orange
        }
    }

    @MainActor
    private func presentDeckAndLoadProducts() async {
        guard self.isDeckPresented == false else {
            return
        }

        await Task.yield()
        guard Task.isCancelled == false else {
            return
        }

        withAnimation(self.reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.58, dampingFraction: 0.82)) {
            self.isDeckPresented = true
        }

        await self.store.loadProducts()
    }

    @MainActor
    private func presentStoreKitPurchase(for plan: InAppPurchasePlan) async {
        guard self.interactionIsLocked == false else {
            return
        }

        self.selectedProductID = plan.productID
        withAnimation(self.reduceMotion ? .easeIn(duration: 0.1) : .easeIn(duration: 0.28)) {
            self.isDeckPresented = false
        }

        do {
            try await Task.sleep(for: self.reduceMotion ? .milliseconds(100) : .milliseconds(300))
        } catch {
            return
        }

        guard Task.isCancelled == false else {
            return
        }

        await self.store.purchase(plan)

        guard Task.isCancelled == false else {
            return
        }

        self.selectedProductID = nil
        withAnimation(self.reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.58, dampingFraction: 0.82)) {
            self.isDeckPresented = true
        }
        self.purchaseTask = nil
    }

    private func deckTravelDistance(in geometry: GeometryProxy) -> CGFloat {
        guard self.reduceMotion == false else {
            return 0
        }

        return max(geometry.size.height * 0.9, 640)
    }

    private func deckAnimation(for order: Int) -> Animation {
        if self.reduceMotion {
            return .easeInOut(duration: 0.12)
        }

        if self.isDeckPresented {
            return .spring(response: 0.58, dampingFraction: 0.82)
                .delay(Double(order) * 0.055)
        }

        return .easeIn(duration: 0.28)
    }

    private func startGlowAnimationIfNeeded() {
        guard self.reduceMotion == false,
              self.glowPhase == false else {
            return
        }

        self.glowPhase = true
    }
}
