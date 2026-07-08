import Foundation
import SwiftUI
import BrowseCraftCore

struct VideoSourceDebugView: View {
    @ObservedObject var viewModel: SourcesViewModel
    let entryURL: String
    let sourceName: String?
    let configuration: ManualVideoSourceConfigurationDraft
    @Environment(\.dismiss) private var dismiss

    @State private var debugEntryURL: String
    @State private var debugResult: ManualVideoSourceDebugResult?
    @State private var isRunning: Bool = false
    @State private var errorMessage: String?

    init(
        viewModel: SourcesViewModel,
        entryURL: String,
        sourceName: String?,
        configuration: ManualVideoSourceConfigurationDraft
    ) {
        self.viewModel = viewModel
        self.entryURL = entryURL
        self.sourceName = sourceName
        self.configuration = configuration
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
                    LabeledContent("Adapter", value: self.configuration.adapter.debugTitle)
                    LabeledContent("Entry", value: self.configuration.entryKind.debugTitle)
                    Text("Run the video runtime with the current manual rule. Debug does not save the source.")
                        .foregroundStyle(.secondary)
                }

                if self.isRunning {
                    Section("Status") {
                        ProgressView("Running debug...")
                    }
                } else if let debugResult: ManualVideoSourceDebugResult = self.debugResult {
                    VideoDebugResultView(result: debugResult)
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
        self.debugResult = nil

        let debugResult: ManualVideoSourceDebugResult? = await self.viewModel.debugManualVideoSource(
            entryURLString: self.debugEntryURL,
            name: self.sourceName,
            configuration: self.configuration
        )

        self.isRunning = false

        guard let debugResult: ManualVideoSourceDebugResult else {
            self.errorMessage = self.viewModel.errorMessage ?? "Failed to debug video source."
            return
        }

        self.debugResult = debugResult
    }
}

private extension VideoAdapter {
    var debugTitle: String {
        switch self {
        case .genericHTML:
            return "Generic HTML"
        case .macCMS:
            return "MacCMS"
        case .webView:
            return "WebView"
        case .plugin:
            return "Plugin"
        }
    }
}

private extension VideoSourceEntryKind {
    var debugTitle: String {
        switch self {
        case .home:
            return "Home"
        case .category:
            return "Category"
        case .list:
            return "List"
        case .detail:
            return "Detail"
        case .play:
            return "Play"
        }
    }
}
