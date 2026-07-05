import SwiftUI

// 中文注释：AddSourceView.swift 是中性的添加来源入口，具体导入能力由 SourceImportOption 决定。

struct AddSourceView: View {
    @ObservedObject var viewModel: SourcesViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var isShowingAddRuleSourceView: Bool = false
    @State private var isShowingImportWebsiteRulePackageView: Bool = false
    @State private var isShowingRSSFeedImportView: Bool = false
    @State private var unavailableOption: SourceImportOptionKind?

    private let options: [SourceImportOption] = SourceImportOption.defaultOptions

    var body: some View {
        NavigationView {
            Form {
                Section("Source") {
                    self.optionButton(for: .comicSource)
                    self.optionButton(for: .videoSource)
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
            .sheet(isPresented: self.$isShowingRSSFeedImportView) {
                RSSFeedSourceImportView(viewModel: self.viewModel)
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
                    Text(self.unavailableOptionMessage)
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
        case .comicSource, .videoSource:
            self.unavailableOption = option.kind
        case .websiteRuleJSON:
            self.isShowingAddRuleSourceView = true
        case .rulePackageJSON:
            self.isShowingImportWebsiteRulePackageView = true
        case .rssFeedURL:
            self.isShowingRSSFeedImportView = true
        case .scriptSource:
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

    private var unavailableOptionMessage: String {
        switch self.unavailableOption {
        case .comicSource:
            return "Comic sources currently use Website Rule JSON from Advanced."
        case .videoSource:
            return "Video sources currently use Website Rule JSON from Advanced."
        case .scriptSource:
            return "Script Source is not available yet."
        case .websiteRuleJSON, .rulePackageJSON, .rssFeedURL, nil:
            return "This source type is not available yet."
        }
    }
}

private struct RSSFeedSourceImportView: View {
    @ObservedObject var viewModel: SourcesViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var entryURL: String = ""
    @State private var recommendation: SourceImportRecommendation?
    @State private var isShowingInvalidRSSAlert: Bool = false

    var body: some View {
        NavigationView {
            Form {
                Section("RSS Feed") {
                    TextField(
                        "Feed URL",
                        text: self.$entryURL
                    )
                    .autocapitalization(.none)
                    .keyboardType(.URL)

                    Button("Validate") {
                        self.validate()
                    }
                    .disabled(self.entryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let recommendation: SourceImportRecommendation = self.recommendation {
                    Section("Result") {
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
            .navigationTitle("RSS Feed")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        self.dismiss()
                    }
                }
            }
            .alert(
                "Invalid RSS Feed",
                isPresented: self.$isShowingInvalidRSSAlert,
                actions: {
                    Button("OK", role: .cancel) {}
                },
                message: {
                    Text("This URL does not look like an RSS feed. Use a direct .rss, .xml, /rss, or /feed URL.")
                }
            )
        }
    }

    private func validate() {
        let draft: SourceImportDraft = SourceImportDraft(
            entryURL: self.entryURL,
            contentType: .article,
            sourceType: .rss,
            configurationKind: .rss
        )
        let recommendation: SourceImportRecommendation = self.viewModel.recommendSourceImport(
            draft: draft,
            selectedOptionKind: .rssFeedURL
        )
        self.recommendation = recommendation
        self.isShowingInvalidRSSAlert = recommendation.isStrongRecommendation == false
    }
}

private extension SourceImportOptionKind {
    var displayTitle: String {
        switch self {
        case .comicSource:
            return "Comics"
        case .videoSource:
            return "Video"
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
        case .comicSource:
            return "book.pages"
        case .videoSource:
            return "play.rectangle"
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
        case .comicSource:
            return "Comics"
        case .videoSource:
            return "Video"
        case .rssFeedURL:
            return "RSS Feed"
        case .websiteRuleJSON, .rulePackageJSON:
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
