import SwiftUI

// 中文注释：ImportWebsiteRulePackageView.swift 是网站规则包导入界面，属于高级规则路径。

struct ImportWebsiteRulePackageView: View {
    @ObservedObject var viewModel: SourcesViewModel
    @Environment(\.dismiss) private var dismiss
    var completion: (() -> Void)?

    @State private var packageJSON: String = ""

    var body: some View {
        NavigationView {
            Form {
                Section("Website Rule Package JSON") {
                    TextEditor(text: self.$packageJSON)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 260)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("Import Website Rule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        self.dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        if self.viewModel.importRulePackage(packageJSON: self.packageJSON) != nil {
                            self.completion?()
                            self.dismiss()
                        }
                    }
                    .disabled(self.packageJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
