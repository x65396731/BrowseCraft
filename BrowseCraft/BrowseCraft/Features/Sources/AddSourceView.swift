import SwiftUI

// 中文注释：AddSourceView.swift 属于界面功能层，用于说明本文件承载的核心职责。

/// 中文注释：AddSourceView 是 struct，负责本模块中的对应职责。
struct AddSourceView: View {
    @ObservedObject var viewModel: SourcesViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTemplate: RuleTemplate = .primaryBuiltIn
    @State private var name: String = RuleTemplate.primaryBuiltIn.sourceName
    @State private var baseURL: String = RuleTemplate.primaryBuiltIn.baseURL
    @State private var ruleJSON: String = RuleTemplate.primaryBuiltIn.ruleJSON

    var body: some View {
        NavigationView {
            Form {
                Section("Template") {
                    Picker(
                        "Rule",
                        selection: self.$selectedTemplate
                    ) {
                        ForEach(RuleTemplate.allCases) { template in
                            Text(template.title)
                                .tag(template)
                        }
                    }
                }

                Section("Source") {
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

                Section("Rule JSON") {
                    TextEditor(text: self.$ruleJSON)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 320)
                        .autocapitalization(.none)
                }
            }
            .navigationTitle("Add Source")
            .onChange(of: self.selectedTemplate) { _, newTemplate in
                self.applyTemplate(newTemplate)
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
                            let didSave: Bool = self.viewModel.addSource(
                                name: self.name,
                                baseURL: self.baseURL,
                                ruleJSON: self.ruleJSON
                            )

                            if didSave {
                                self.dismiss()
                            }
                        }
                    )
                }
            }
        }
    }

    /// 中文注释：applyTemplate 方法封装当前类型的一段业务或界面行为。
    private func applyTemplate(_ template: RuleTemplate) {
        self.name = template.sourceName
        self.baseURL = template.baseURL
        self.ruleJSON = template.ruleJSON
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
