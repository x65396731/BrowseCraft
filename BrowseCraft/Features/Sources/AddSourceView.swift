import SwiftUI

// 中文注释：AddSourceView.swift 是中性的添加来源入口，具体导入能力由 SourceImportOption 决定。

struct AddSourceView: View {
    @ObservedObject var viewModel: SourcesViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var isShowingAddRuleSourceView: Bool = false
    @State private var isShowingImportWebsiteRulePackageView: Bool = false
    @State private var isShowingWebsiteURLImportView: Bool = false
    @State private var unavailableOption: SourceImportOptionKind?

    private let options: [SourceImportOption] = SourceImportOption.defaultOptions

    var body: some View {
        NavigationView {
            Form {
                Section("Source") {
                    self.optionButton(for: .websiteURL)
                    self.optionButton(for: .rssFeedURL)
                }

                Section("Advanced") {
                    self.optionButton(for: .websiteRuleJSON)
                    self.optionButton(for: .rulePackageJSON)
                    self.optionButton(for: .scriptSource)
                }
            }
            .navigationTitle("Add Source")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        self.dismiss()
                    }
                }
            }
            .sheet(isPresented: self.$isShowingAddRuleSourceView) {
                AddRuleSourceView(
                    viewModel: self.viewModel,
                    completion: {
                        self.dismiss()
                    }
                )
            }
            .sheet(isPresented: self.$isShowingWebsiteURLImportView) {
                WebsiteURLSourceImportView(viewModel: self.viewModel)
            }
            .sheet(isPresented: self.$isShowingImportWebsiteRulePackageView) {
                ImportWebsiteRulePackageView(
                    viewModel: self.viewModel,
                    completion: {
                        self.dismiss()
                    }
                )
            }
            .alert(
                "Source Type Unavailable",
                isPresented: self.unavailableOptionBinding,
                actions: {
                    Button("OK", role: .cancel) {}
                },
                message: {
                    Text("This source type is not available yet.")
                }
            )
        }
    }

    @ViewBuilder
    private func optionButton(for kind: SourceImportOptionKind) -> some View {
        if let option: SourceImportOption = self.options.first(where: { item in item.kind == kind }) {
            Button(
                action: {
                    self.select(option)
                },
                label: {
                    Label(
                        option.kind.displayTitle,
                        systemImage: option.kind.systemImageName
                    )
                }
            )
        }
    }

    private func select(_ option: SourceImportOption) {
        switch option.kind {
        case .websiteURL:
            self.isShowingWebsiteURLImportView = true
        case .websiteRuleJSON:
            self.isShowingAddRuleSourceView = true
        case .rulePackageJSON:
            self.isShowingImportWebsiteRulePackageView = true
        case .rssFeedURL, .scriptSource:
            self.unavailableOption = option.kind
        }
    }

    private var unavailableOptionBinding: Binding<Bool> {
        return Binding<Bool>(
            get: {
                return self.unavailableOption != nil
            },
            set: { newValue in
                if newValue == false {
                    self.unavailableOption = nil
                }
            }
        )
    }
}

private struct WebsiteURLSourceImportView: View {
    @ObservedObject var viewModel: SourcesViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var entryURL: String = ""
    @State private var recommendation: SourceImportRecommendation?

    var body: some View {
        NavigationView {
            Form {
                Section("Website") {
                    TextField(
                        "URL",
                        text: self.$entryURL
                    )
                    .autocapitalization(.none)
                    .keyboardType(.URL)

                    Button("Analyze") {
                        self.analyze()
                    }
                    .disabled(self.entryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let recommendation: SourceImportRecommendation = self.recommendation {
                    Section("Recommendation") {
                        LabeledContent(
                            "Type",
                            value: recommendation.userFacingTitle
                        )
                        LabeledContent(
                            "Confidence",
                            value: recommendation.confidence.displayTitle
                        )

                        ForEach(recommendation.warnings, id: \.self) { warning in
                            Text(warning)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Website URL")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        self.dismiss()
                    }
                }
            }
        }
    }

    private func analyze() {
        let draft: SourceImportDraft = SourceImportDraft(
            entryURL: self.entryURL,
            sourceType: .html
        )
        self.recommendation = self.viewModel.recommendSourceImport(draft: draft)
    }
}

private extension SourceImportOptionKind {
    var displayTitle: String {
        switch self {
        case .websiteURL:
            return "Website URL"
        case .websiteRuleJSON:
            return "Website Rule JSON"
        case .rulePackageJSON:
            return "Website Rule Package"
        case .rssFeedURL:
            return "RSS Feed"
        case .scriptSource:
            return "Script Source"
        }
    }

    var systemImageName: String {
        switch self {
        case .websiteURL:
            return "link"
        case .websiteRuleJSON:
            return "curlybraces"
        case .rulePackageJSON:
            return "shippingbox"
        case .rssFeedURL:
            return "dot.radiowaves.left.and.right"
        case .scriptSource:
            return "terminal"
        }
    }
}

private extension SourceImportRecommendation {
    var userFacingTitle: String {
        switch self.optionKind {
        case .rssFeedURL:
            return "RSS Feed"
        case .websiteRuleJSON, .rulePackageJSON, .websiteURL:
            return "Website Rule"
        case .scriptSource:
            return "Script Source"
        case nil:
            return "Source"
        }
    }
}

private extension SourceImportRecommendationConfidence {
    var displayTitle: String {
        switch self {
        case .low:
            return "Low"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        }
    }
}
