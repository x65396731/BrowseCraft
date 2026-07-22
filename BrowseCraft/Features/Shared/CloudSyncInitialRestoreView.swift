import SwiftUI

@MainActor
struct CloudSyncInitialRestoreView: View {
    let state: CloudSyncInitialRestoreState
    let retryAction: () async -> Void

    @State private var isRetrying: Bool = false

    var body: some View {
        Group {
            switch self.state {
            case .waitingForCloud:
                self.progressContent(
                    title: "Waiting for iCloud",
                    message: "Your sources and favorites will appear after iCloud becomes available."
                )

            case .restoring:
                self.progressContent(
                    title: "Restoring from iCloud",
                    message: "Downloading and merging your saved data."
                )

            case .failed(let message):
                ContentUnavailableView {
                    Label("iCloud Restore Failed", systemImage: "exclamationmark.icloud")
                } description: {
                    Text(message)
                } actions: {
                    Button(self.isRetrying ? "Retrying…" : "Retry") {
                        self.retry()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(self.isRetrying)
                }

            case .notRequired, .restored:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func progressContent(title: String, message: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .accessibilityElement(children: .combine)
    }

    private func retry() {
        guard self.isRetrying == false else {
            return
        }
        self.isRetrying = true

        Task {
            await self.retryAction()
            self.isRetrying = false
        }
    }
}
