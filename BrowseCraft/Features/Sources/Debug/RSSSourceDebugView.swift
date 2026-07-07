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
                Section("Input") {
                    TextField("URL", text: self.$debugEntryURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .disabled(self.isRunning)
                }

                Section("Runtime") {
                    LabeledContent("Type", value: RuntimeSourceImportKind.rss.displayTitle)
                    Text(RuntimeSourceImportKind.rss.debugSummary)
                        .foregroundStyle(.secondary)

                    Button(self.isRunning ? "Running..." : "Run Debug") {
                        Task {
                            await self.runDebug()
                        }
                    }
                    .disabled(self.canRun == false)
                }

                Section("RSS Debug") {
                    Text("RSS debug uses fixed RSS/Atom parsing. Selector editing is not available for feeds.")
                        .foregroundStyle(.secondary)
                }

                if self.isRunning {
                    Section("Status") {
                        ProgressView("Running debug...")
                    }
                } else if let result: RuntimeRSSDebugResult = self.result {
                    RSSSourceDebugResultSection(result: result)
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

struct RSSSourceDebugResultSection: View {
    let result: RuntimeRSSDebugResult

    var body: some View {
        Section("Request") {
            LabeledContent("URL", value: self.result.entryURL.absoluteString)
            LabeledContent("Bytes", value: "\(self.result.byteCount)")
        }

        Section("Parser") {
            if let parserError: String = self.result.parserError {
                LabeledContent("Status", value: "failed")
                Text(parserError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            } else {
                LabeledContent("Status", value: "success")
            }

            if let feedTitle: String = self.result.feedTitle {
                LabeledContent("Feed title", value: feedTitle)
            }
            if let itemCount: Int = self.result.itemCount {
                LabeledContent("Items", value: "\(itemCount)")
            }
            if let firstItemTitle: String = self.result.firstItemTitle {
                LabeledContent("First item", value: firstItemTitle)
            }
        }

        Section("Logs") {
            ForEach(self.result.logLines, id: \.self) { line in
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }

        Section("Raw Preview") {
            Text(self.result.rawPreview.isEmpty ? "No body returned." : self.result.rawPreview)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}
