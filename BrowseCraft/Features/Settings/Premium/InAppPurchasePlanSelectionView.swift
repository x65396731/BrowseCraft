import SwiftUI

struct InAppPurchasePlanSelectionView: View {
    @ObservedObject var store: InAppPurchaseStore
    let closeAction: () -> Void

    private let plans: [InAppPurchasePlan] = [
        .year,
        .quarter,
        .month
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("In-App Purchase")
                        .font(.largeTitle.bold())

                    Text("Choose a plan for premium access.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)

                VStack(spacing: 12) {
                    ForEach(self.plans) { plan in
                        Button(
                            action: {
                                Task {
                                    await self.store.purchase(plan)
                                }
                            },
                            label: {
                                InAppPurchasePlanButton(
                                    plan: plan,
                                    priceText: self.store.priceText(for: plan),
                                    isLoading: self.store.activeProductID == plan.productID
                                )
                            }
                        )
                        .buttonStyle(.plain)
                        .disabled(self.store.isLoading || self.store.activeProductID != nil)
                    }
                }
                .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 10) {
                    Label("Cloud sync across devices", systemImage: "icloud")
                    Label("Larger cache limits", systemImage: "externaldrive")
                    Label("Future AI rule assistant", systemImage: "sparkles")
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 8)

                if let message: String = self.store.statusMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 20)
                }

                HStack {
                    Button(
                        action: {
                            Task {
                                await self.store.restorePurchases()
                            }
                        },
                        label: {
                            Label("Restore", systemImage: "arrow.clockwise")
                        }
                    )
                    .buttonStyle(.bordered)
                    .disabled(self.store.isLoading || self.store.activeProductID != nil)

                    Spacer()

                    NavigationLink(destination: MoreInAppPurchasePlansView(store: self.store, closeAction: self.closeAction)) {
                        Label("More Plans", systemImage: "ellipsis.circle")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("In-App Purchase")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await self.store.loadProducts()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(
                    action: self.closeAction,
                    label: {
                        Image(systemName: "xmark")
                    }
                )
                .accessibilityLabel("Close")
            }
        }
    }
}
