import SwiftUI

struct HistoryUnavailableView: View {
    let message: String

    var body: some View {
        EmptyStateView(
            systemImage: "exclamationmark.triangle",
            title: NSLocalizedString("Unavailable", comment: ""),
            message: self.message
        )
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
    }
}
