import SwiftUI

struct AppBootstrapFailureView: View {
    let failure: AppBootstrapFailure

    var body: some View {
        ContentUnavailableView {
            Label(self.failure.title, systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            VStack(spacing: 12) {
                Text(self.failure.message)
                Text(self.failure.recoverySuggestion)
                Text(self.failure.diagnosticCode)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding()
    }
}
