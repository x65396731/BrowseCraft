import SwiftUI

struct MoreInAppPurchasePlansView: View {
    @ObservedObject var store: InAppPurchaseStore
    let closeAction: () -> Void

    private let plans: [InAppPurchasePlan] = [
        .siteSlot1,
        .siteSlot5,
        .siteSlot10,
        .siteSlot30
    ]

    var body: some View {
        List {
            ForEach(self.plans) { plan in
                Button(
                    action: {
                        Task {
                            await self.store.purchase(plan)
                        }
                    },
                    label: {
                        HStack(spacing: 12) {
                            Image(systemName: plan.systemImage)
                                .foregroundColor(.accentColor)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(plan.title)
                                Text(plan.subtitle)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if self.store.activeProductID == plan.productID {
                                ProgressView()
                            } else if self.store.isPurchased(plan) {
                                Text("Purchased")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.secondary)
                            } else {
                                Text(self.store.priceText(for: plan))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                )
                .buttonStyle(.plain)
                .disabled(
                    self.store.isLoading ||
                    self.store.activeProductID != nil ||
                    self.store.isPurchased(plan)
                )
                .padding(.vertical, 4)
            }

            Section {
                Button(
                    action: {
                        Task {
                            await self.store.purchase(.removeAds)
                        }
                    },
                    label: {
                        HStack(spacing: 12) {
                            Image(systemName: InAppPurchasePlan.removeAds.systemImage)
                                .foregroundColor(.accentColor)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(InAppPurchasePlan.removeAds.title)
                                Text(InAppPurchasePlan.removeAds.subtitle)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if self.store.activeProductID == InAppPurchasePlan.removeAds.productID {
                                ProgressView()
                            } else if self.store.isPurchased(.removeAds) {
                                Text("Purchased")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.secondary)
                            } else {
                                Text(self.store.priceText(for: .removeAds))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                )
                .buttonStyle(.plain)
                .disabled(
                    self.store.isLoading ||
                    self.store.activeProductID != nil ||
                    self.store.isPurchased(.removeAds)
                )
            }
        }
        .navigationTitle("More Plans")
        .navigationBarTitleDisplayMode(.inline)
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
