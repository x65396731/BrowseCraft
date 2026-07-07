import Foundation
import SwiftUI

struct RuleSourceDebugView: View {
    @ObservedObject var viewModel: SourcesViewModel
    let entryURL: String
    let sourceName: String?
    @Binding var ruleJSON: String
    private let candidateDraftApplier: RuleCandidateDraftApplier = RuleCandidateDraftApplier()
    @Environment(\.dismiss) private var dismiss

    @State private var debugEntryURL: String
    @State private var validationResult: SiteRuleValidationResult = SiteRuleValidationResult(rule: nil, issues: [])
    @State private var session: RuleDebugSession?
    @State private var isRunning: Bool = false
    @State private var errorMessage: String?
    @State private var isShowingResult: Bool = false

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
            self.content
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

                    if self.session != nil {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(self.isShowingResult ? "Edit Rule" : "Result") {
                                self.isShowingResult.toggle()
                            }
                            .disabled(self.isRunning)
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if self.isShowingResult, self.session != nil {
            RuleDebugResultView(
                session: self.session,
                applyCandidate: { candidate in
                    self.applyCandidateToDraft(candidate)
                },
                canApplyCandidate: { candidate in
                    self.canApplyCandidateToDraft(candidate)
                },
                debugDetail: { _, _ in },
                debugReader: { _, _ in }
            )
        } else {
            self.editorForm
        }
    }

    private var editorForm: some View {
        Form {
            SourceDebugInputSection(
                entryURL: self.$debugEntryURL,
                isRunning: self.isRunning
            )

            SourceDebugRunSection(
                kind: .comic,
                isRunning: self.isRunning,
                canRun: self.canRun,
                runAction: {
                    Task {
                        await self.runDebug()
                    }
                }
            )

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
                Section("Status") {
                    LabeledContent("Items", value: "\(session.previewItems.count)")
                    LabeledContent("Issues", value: "\(session.issues.count)")
                    Button("Show Debug Result") {
                        self.isShowingResult = true
                    }
                }
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
        self.isShowingResult = true
    }

    private func formatRuleJSON() {
        guard let rule: SiteRule = self.validationResult.rule else {
            return
        }

        self.ruleJSON = self.viewModel.formattedRuleJSON(for: rule)
        self.validationResult = self.viewModel.validateRuleJSON(self.ruleJSON)
    }

    private func applyCandidateToDraft(_ candidate: RuleCandidate) {
        guard var rule: SiteRule = self.validationResult.rule else {
            return
        }

        let didApply: Bool = self.candidateDraftApplier.apply(
            candidate: candidate,
            stage: self.session?.input.stage,
            ruleID: self.session?.input.ruleID,
            rule: &rule
        )

        guard didApply else {
            return
        }

        self.ruleJSON = self.viewModel.formattedRuleJSON(for: rule)
        self.validationResult = self.viewModel.validateRuleJSON(self.ruleJSON)
        self.isShowingResult = false
    }

    private func canApplyCandidateToDraft(_ candidate: RuleCandidate) -> Bool {
        return self.validationResult.rule != nil
            && self.candidateDraftApplier.canApply(
                candidate: candidate,
                stage: self.session?.input.stage
            )
    }
}
