import Foundation
import SwiftUI

struct ComicSourceRuleDebugView: View {
    @ObservedObject var viewModel: SourcesViewModel
    let entryURL: String
    let sourceName: String?
    @Binding var ruleJSON: String
    @Environment(\.dismiss) private var dismiss

    @State private var debugEntryURL: String
    @State private var validationResult: SiteRuleValidationResult = SiteRuleValidationResult(rule: nil, issues: [])
    @State private var session: RuleDebugSession?
    @State private var isRunning: Bool = false
    @State private var errorMessage: String?

    init(
        viewModel: SourcesViewModel,
        entryURL: String,
        sourceName: String?,
        ruleJSON: Binding<String>
    ) {
        self.viewModel = viewModel
        self.entryURL = entryURL
        self.sourceName = sourceName
        self._ruleJSON = ruleJSON
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
                    LabeledContent("Type", value: RuntimeSourceImportKind.comic.displayTitle)
                    Text(RuntimeSourceImportKind.comic.debugSummary)
                        .foregroundStyle(.secondary)

                    Button(self.isRunning ? "Running..." : "Run Debug") {
                        Task {
                            await self.runDebug()
                        }
                    }
                    .disabled(self.canRun == false)
                }

                Section("Comic Rule Debug") {
                    Text("Runs list debug against the current Rule JSON. Detail and reader debug stay in the saved rule detail view for now.")
                        .foregroundStyle(.secondary)
                }

                RuleJSONEditorView(
                    ruleJSON: self.$ruleJSON,
                    validationResult: self.validationResult,
                    isEditable: self.isRunning == false,
                    formatAction: {
                        self.formatRuleJSON()
                    }
                )

                if self.isRunning {
                    Section("Status") {
                        ProgressView("Running debug...")
                    }
                } else if let session: RuleDebugSession = self.session {
                    RuleDebugSessionSummarySection(session: session)
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
            .onAppear {
                self.validationResult = self.viewModel.validateRuleJSON(self.ruleJSON)
            }
            .onChange(of: self.ruleJSON) { _, newValue in
                self.validationResult = self.viewModel.validateRuleJSON(newValue)
            }
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
        return self.validationResult.canSave
            && self.isRunning == false
    }

    @MainActor
    private func runDebug() async {
        self.isRunning = true
        self.errorMessage = nil
        self.session = nil

        let session: RuleDebugSession? = await self.viewModel.debugRuntimeComicRule(
            name: self.sourceName,
            baseURL: self.debugEntryURL,
            ruleJSON: self.ruleJSON
        )

        self.isRunning = false

        guard let session: RuleDebugSession else {
            self.errorMessage = self.viewModel.errorMessage ?? "Failed to debug comic rule."
            return
        }

        self.session = session
    }

    private func formatRuleJSON() {
        guard let rule: SiteRule = self.validationResult.rule else {
            return
        }

        self.ruleJSON = self.viewModel.formattedRuleJSON(for: rule)
        self.validationResult = self.viewModel.validateRuleJSON(self.ruleJSON)
    }
}
