import SwiftUI

struct HistoryUnavailableView: View {
    let message: String

    var body: some View {
        EmptyStateView(
            systemImage: "exclamationmark.triangle",
            title: "Unavailable",
            message: self.message
        )
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
    }
}
