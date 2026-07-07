import SwiftUI

/// 中文注释：WebsiteRuleImportView 负责 Advanced 里的 Website Rule JSON 导入。
struct WebsiteRuleImportView: View {
    @ObservedObject var viewModel: SourcesViewModel
    @Environment(\.dismiss) private var dismiss
    var completion: (() -> Void)?

    @State private var name: String = ""
    @State private var baseURL: String = ""
    @State private var ruleJSON: String = ""
    @State private var validationResult: SiteRuleValidationResult = SiteRuleValidationResult(rule: nil, issues: [])

    var body: some View {
        NavigationStack {
            Form {
                Section("Rule-backed Source") {
                    TextField(
                        "Name",
                        text: self.$name
                    )

                    TextField(
                        "Base URL",
                        text: self.$baseURL
                    )
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                }

                RuleJSONEditorView(
                    ruleJSON: self.$ruleJSON,
                    validationResult: self.validationResult,
                    isEditable: true,
                    formatAction: {
                        self.formatRuleJSON()
                    }
                )
            }
            .navigationTitle("Add Website Rule")
            .onAppear {
                self.validationResult = self.viewModel.validateRuleJSON(self.ruleJSON)
            }
            .onChange(of: self.ruleJSON) { _, newValue in
                self.validationResult = self.viewModel.validateRuleJSON(newValue)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(
                        "Cancel",
                        action: {
                            self.dismiss()
                        }
                    )
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(
                        "Save",
                        action: {
                            Task {
                                let didSave: Bool = await self.viewModel.addRuleSource(
                                    name: self.name,
                                    baseURL: self.baseURL,
                                    ruleJSON: self.ruleJSON
                                )

                                if didSave {
                                    self.completion?()
                                    self.dismiss()
                                }
                            }
                        }
                    )
                    .disabled(self.validationResult.canSave == false)
                }
            }
        }
    }

    private func formatRuleJSON() {
        guard let rule: SiteRule = self.validationResult.rule else {
            return
        }

        self.ruleJSON = self.viewModel.formattedRuleJSON(for: rule)
        self.validationResult = self.viewModel.validateRuleJSON(self.ruleJSON)
    }
}
