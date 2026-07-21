import SwiftUI

struct MoreInAppPurchasePlansView: View {
    @ObservedObject var store: InAppPurchaseStore
    let closeAction: () -> Void

    private let plans: [InAppPurchasePlan] = InAppPurchasePlan.activePlans

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
                                Text(self.store.priceText(for: plan) ?? "Unavailable")
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
