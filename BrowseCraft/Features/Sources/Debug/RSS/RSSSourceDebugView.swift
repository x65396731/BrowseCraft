import Foundation
import SwiftUI

struct RSSSourceDebugView: View {
    @ObservedObject var viewModel: SourcesViewModel
    let entryURL: String
    @Environment(\.dismiss) private var dismiss

    @State private var debugEntryURL: String
    @State private var result: RuntimeRSSDebugResult?
    @State private var isRunning: Bool = false
    @State private var errorMessage: String?

    init(viewModel: SourcesViewModel, entryURL: String) {
        self.viewModel = viewModel
        self.entryURL = entryURL
        self._debugEntryURL = State(initialValue: entryURL)
    }

    var body: some View {
        NavigationStack {
            Form {
                SourceDebugInputSection(
                    entryURL: self.$debugEntryURL,
                    isRunning: self.isRunning
                )

                SourceDebugRunSection(
                    kind: .rss,
                    isRunning: self.isRunning,
                    canRun: self.canRun,
                    runAction: {
                        Task {
                            await self.runDebug()
                        }
                    }
                )

                Section("RSS Debug") {
                    Text("RSS debug uses fixed RSS/Atom parsing. Selector editing is not available for feeds.")
                        .foregroundStyle(.secondary)
                }

                if self.isRunning {
                    Section("Status") {
                        ProgressView("Running debug...")
                    }
                } else if let result: RuntimeRSSDebugResult = self.result {
                    RSSDebugResultView(result: result)
                } else if let errorMessage: String = self.errorMessage {
                    Section("Status") {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                } else {
                    Section("Status") {
                        Text("Run debug to inspect this source.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Debug Source")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        self.dismiss()
                    }
                    .disabled(self.isRunning)
                }
            }
        }
    }

    private var canRun: Bool {
        return self.debugEntryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && self.isRunning == false
    }

    @MainActor
    private func runDebug() async {
        self.isRunning = true
        self.errorMessage = nil
        self.result = nil

        let result: RuntimeRSSDebugResult? = await self.viewModel.debugRSSRuntimeSource(
            entryURLString: self.debugEntryURL
        )

        self.isRunning = false

        guard let result: RuntimeRSSDebugResult else {
            self.errorMessage = self.viewModel.errorMessage ?? "Failed to debug RSS feed."
            return
        }

        self.result = result
    }
}
