import SwiftUI

struct InAppPurchasePlanButton: View {
    let plan: InAppPurchasePlan
    let priceText: String
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: self.plan.systemImage)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(self.plan.title)
                    .font(.headline)

                Text(self.plan.subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }

            Spacer()

            if self.isLoading {
                ProgressView()
            } else {
                Text(self.priceText)
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
