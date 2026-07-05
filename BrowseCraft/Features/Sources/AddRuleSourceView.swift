import SwiftUI

// 中文注释：AddRuleSourceView.swift 属于界面功能层，用于说明本文件承载的核心职责。

/// 中文注释：AddRuleSourceView 是网站规则导入入口，不代表通用添加来源流程。
struct AddRuleSourceView: View {
    @ObservedObject var viewModel: SourcesViewModel
    @Environment(\.dismiss) private var dismiss
    var completion: (() -> Void)?

    @State private var selectedTemplate: RuleTemplate = .primaryBuiltIn
    @State private var name: String = RuleTemplate.primaryBuiltIn.sourceName
    @State private var baseURL: String = RuleTemplate.primaryBuiltIn.baseURL
    @State private var ruleJSON: String = RuleTemplate.primaryBuiltIn.ruleJSON
    @State private var validationResult: SiteRuleValidationResult = SiteRuleValidationResult(rule: nil, issues: [])

    var body: some View {
        NavigationView {
            Form {
                Section("Website Rule Template") {
                    Picker(
                        "Website Rule",
                        selection: self.$selectedTemplate
                    ) {
                        ForEach(RuleTemplate.allCases) { template in
                            Text(template.title)
                                .tag(template)
                        }
                    }
                }

                Section("Rule-backed Source") {
                    TextField(
                        "Name",
                        text: self.$name
                    )

                    TextField(
                        "Base URL",
                        text: self.$baseURL
                    )
                    .autocapitalization(.none)
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
            .onChange(of: self.selectedTemplate) { _, newTemplate in
                self.applyTemplate(newTemplate)
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
                            let didSave: Bool = self.viewModel.addRuleSource(
                                name: self.name,
                                baseURL: self.baseURL,
                                ruleJSON: self.ruleJSON
                            )

                            if didSave {
                                self.completion?()
                                self.dismiss()
                            }
                        }
                    )
                    .disabled(self.validationResult.canSave == false)
                }
            }
        }
    }

    /// 中文注释：applyTemplate 方法封装当前类型的一段业务或界面行为。
    private func applyTemplate(_ template: RuleTemplate) {
        self.name = template.sourceName
        self.baseURL = template.baseURL
        self.ruleJSON = template.ruleJSON
        self.validationResult = self.viewModel.validateRuleJSON(template.ruleJSON)
    }

    private func formatRuleJSON() {
        guard let rule: SiteRule = self.validationResult.rule else {
            return
        }

        self.ruleJSON = self.viewModel.formattedRuleJSON(for: rule)
        self.validationResult = self.viewModel.validateRuleJSON(self.ruleJSON)
    }
}

private enum RuleTemplate: String, CaseIterable, Identifiable {
    case example
    case primaryBuiltIn

    var id: String {
        return self.rawValue
    }

    var title: String {
        switch self {
        case .example:
            return "Example"
        case .primaryBuiltIn:
            return BuiltInSource.primaryBuiltIn().name
        }
    }

    var sourceName: String {
        switch self {
        case .example:
            return ""
        case .primaryBuiltIn:
            return BuiltInSource.primaryBuiltIn().name
        }
    }

    var baseURL: String {
        switch self {
        case .example:
            return ""
        case .primaryBuiltIn:
            return BuiltInSource.primaryBuiltIn().baseURL
        }
    }

    var ruleJSON: String {
        switch self {
        case .example:
            return SiteRule.exampleJSON
        case .primaryBuiltIn:
            return BuiltInSource.primaryBuiltInRuleJSON
        }
    }
}
