import SwiftUI

// 中文注释：RuleJSONEditorView.swift 提供可复用的规则 JSON 编辑与校验区块。

/// 中文注释：RuleJSONEditorView 负责展示规则 JSON 文本、格式化入口和结构校验结果。
struct RuleJSONEditorView: View {
    @Binding var ruleJSON: String
    let validationResult: SiteRuleValidationResult
    let isEditable: Bool
    let formatAction: () -> Void

    var body: some View {
        Section("Rule JSON") {
            HStack(spacing: 8) {
                Label(self.statusTitle, systemImage: self.statusSystemImage)
                    .foregroundColor(self.statusColor)
                Spacer()
                Text("\(self.ruleJSON.count) chars")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            TextEditor(text: self.$ruleJSON)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 320)
                .textInputAutocapitalization(.never)
                .disabled(self.isEditable == false)

            HStack {
                Button(
                    action: self.formatAction,
                    label: {
                        Label("Format JSON", systemImage: "curlybraces")
                    }
                )
                .disabled(self.validationResult.rule == nil || self.isEditable == false)

                Spacer()

                if self.isEditable == false {
                    Label("Read-only", systemImage: "lock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }

        Section("Validation") {
            if self.validationResult.issues.isEmpty {
                Label("Rule JSON is valid.", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                self.issueGroup(title: "Errors", issues: self.validationResult.errors)
                self.issueGroup(title: "Warnings", issues: self.validationResult.warnings)
            }
        }
    }

    private var statusTitle: String {
        if self.validationResult.rule == nil {
            return "Invalid JSON"
        }

        if self.validationResult.errors.isEmpty == false {
            return "\(self.validationResult.errors.count) errors"
        }

        if self.validationResult.warnings.isEmpty == false {
            return "\(self.validationResult.warnings.count) warnings"
        }

        return "Ready to save"
    }

    private var statusSystemImage: String {
        if self.validationResult.rule == nil || self.validationResult.errors.isEmpty == false {
            return "xmark.octagon.fill"
        }

        if self.validationResult.warnings.isEmpty == false {
            return "exclamationmark.triangle.fill"
        }

        return "checkmark.circle.fill"
    }

    private var statusColor: Color {
        if self.validationResult.rule == nil || self.validationResult.errors.isEmpty == false {
            return .red
        }

        if self.validationResult.warnings.isEmpty == false {
            return .orange
        }

        return .green
    }

    private func issueGroup(title: String, issues: [SiteRuleValidationResult.Issue]) -> some View {
        Group {
            if issues.isEmpty == false {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)

                ForEach(issues) { issue in
                    Label(
                        issue.message,
                        systemImage: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundColor(issue.severity == .error ? .red : .orange)
                }
            }
        }
    }
}
