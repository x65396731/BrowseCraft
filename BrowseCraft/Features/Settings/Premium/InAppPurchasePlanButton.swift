import SwiftUI

struct InAppPurchasePlanButton: View {
    enum State: Equatable {
        case loading
        case unavailable
        case available(price: String)
        case purchasing
        case pending
        case purchased

        var accessibilityValue: String {
            switch self {
            case .loading:
                return "Loading price"
            case .unavailable:
                return "Unavailable"
            case .available(let price):
                return price
            case .purchasing:
                return "Purchasing"
            case .pending:
                return "Pending approval"
            case .purchased:
                return "Purchased"
            }
        }

        var isPurchasable: Bool {
            if case .available = self {
                return true
            }

            return false
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let plan: InAppPurchasePlan
    let state: State
    let isSelected: Bool
    let glowPhase: Bool

    private let shape: RoundedRectangle = RoundedRectangle(cornerRadius: 18, style: .continuous)

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: self.plan.systemImage)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(
                    LinearGradient(
                        colors: [.cyan.opacity(0.9), .purple.opacity(0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .shadow(color: .cyan.opacity(0.35), radius: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(self.plan.title)
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)

                Text(self.plan.subtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.68))
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 8)

            self.trailingContent
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 82)
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0.68),
                    Color.indigo.opacity(0.34)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: self.shape
        )
        .overlay {
            self.shape
                .stroke(
                    LinearGradient(
                        colors: self.glowColors,
                        startPoint: self.glowPhase ? .topLeading : .bottomTrailing,
                        endPoint: self.glowPhase ? .bottomTrailing : .topLeading
                    ),
                    lineWidth: self.isSelected ? 3 : 1.6
                )
                .shadow(
                    color: self.isSelected ? .cyan.opacity(0.9) : .purple.opacity(0.48),
                    radius: self.isSelected ? 16 : 9
                )
                .animation(
                    self.reduceMotion
                        ? nil
                        : .linear(duration: 2.2).repeatForever(autoreverses: true),
                    value: self.glowPhase
                )
        }
        .scaleEffect(self.isSelected ? 1.025 : 1)
        .brightness(self.isSelected ? 0.08 : 0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: self.isSelected)
        .contentShape(self.shape)
    }

    @ViewBuilder
    private var trailingContent: some View {
        switch self.state {
        case .loading, .purchasing:
            ProgressView()
                .tint(.white)
                .frame(width: 62)
        case .pending:
            Image(systemName: "clock.badge.exclamationmark.fill")
                .font(.title2)
                .foregroundStyle(.yellow)
                .frame(width: 62)
        case .purchased:
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(.green)
                .frame(width: 62)
        case .unavailable:
            Text("Unavailable")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.58))
                .frame(width: 82)
        case .available(let price):
            Text(price)
                .font(.headline.weight(.black))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.white.opacity(0.12), in: Capsule())
        }
    }

    private var glowColors: [Color] {
        if self.isSelected {
            return [.white, .cyan, .blue, .purple, .white]
        }

        return [
            .cyan.opacity(0.75),
            .blue.opacity(0.45),
            .purple.opacity(0.75),
            .pink.opacity(0.45),
            .cyan.opacity(0.75)
        ]
    }
}
