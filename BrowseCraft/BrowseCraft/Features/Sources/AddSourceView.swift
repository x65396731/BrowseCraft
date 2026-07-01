import SwiftUI

struct AddSourceView: View {
    @ObservedObject var viewModel: SourcesViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var baseURL: String = ""
    @State private var ruleJSON: String = SiteRule.exampleJSON

    var body: some View {
        NavigationView {
            Form {
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
}
