import SwiftUI

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: self.systemImage)
                .font(.system(size: 42, weight: .regular))
                .foregroundColor(.secondary)

            Text(self.title)
                .font(.headline)
                .foregroundColor(.primary)

            Text(self.message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
