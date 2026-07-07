import Foundation
import SwiftUI

struct VideoSourceDebugView: View {
    @ObservedObject var viewModel: SourcesViewModel
    let entryURL: String
    let sourceName: String?
    @Environment(\.dismiss) private var dismiss

    @State private var debugEntryURL: String
    @State private var preview: RuntimeSourcePreviewResult?
    @State private var isRunning: Bool = false
    @State private var errorMessage: String?

    init(
        viewModel: SourcesViewModel,
        entryURL: String,
        sourceName: String?
    ) {
        self.viewModel = viewModel
        self.entryURL = entryURL
        self.sourceName = sourceName
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
                    kind: .video,
                    isRunning: self.isRunning,
                    canRun: self.canRun,
                    runAction: {
                        Task {
                            await self.runDebug()
                        }
                    }
                )

                Section("Video Debug") {
                    Text("Video debug only shows request and URL inspection logs. It does not choose a video adapter.")
                        .foregroundStyle(.secondary)
                }

                if self.isRunning {
                    Section("Status") {
                        ProgressView("Running debug...")
                    }
                } else if let preview: RuntimeSourcePreviewResult = self.preview {
                    VideoDebugResultView(preview: preview)
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
        self.preview = nil

        let preview: RuntimeSourcePreviewResult? = await self.viewModel.previewRuntimeSource(
            kind: .video,
            entryURLString: self.debugEntryURL,
            name: self.sourceName
        )

        self.isRunning = false

        guard let preview: RuntimeSourcePreviewResult else {
            self.errorMessage = self.viewModel.errorMessage ?? "Failed to debug video source."
            return
        }

        self.preview = preview
    }
}
