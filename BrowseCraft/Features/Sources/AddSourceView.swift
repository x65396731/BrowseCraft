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
                RSSFeedSourceImportView(
                    viewModel: self.viewModel,
                    completion: {
                        self.dismiss()
                    }
                )
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
    private enum ImportState: Equatable {
        case idle
        case loading
        case valid
        case invalid(String)
        case saving
        case saved
        case error(String)

        var isWorking: Bool {
            switch self {
            case .loading, .saving:
                return true
            case .idle, .valid, .invalid, .saved, .error:
                return false
            }
        }
    }

    @ObservedObject var viewModel: SourcesViewModel
    let completion: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var entryURL: String = ""
    @State private var sourceName: String = ""
    @State private var recommendation: SourceImportRecommendation?
    @State private var importState: ImportState = .idle

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
                    .disabled(self.importState.isWorking)

                    TextField(
                        "Name (Optional)",
                        text: self.$sourceName
                    )
                    .disabled(self.importState.isWorking)

                    Button(self.primaryButtonTitle) {
                        Task {
                            await self.save()
                        }
                    }
                    .disabled(self.canSubmit == false)
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

                if let message: String = self.statusMessage {
                    Section("Status") {
                        Text(message)
                            .foregroundStyle(self.statusForegroundStyle)
                    }
                }
            }
            .navigationTitle("RSS Feed")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        self.dismiss()
                    }
                    .disabled(self.importState.isWorking)
                }
            }
        }
    }

    private var trimmedEntryURL: String {
        return self.entryURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedSourceName: String? {
        let trimmed: String = self.sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var canSubmit: Bool {
        return self.trimmedEntryURL.isEmpty == false && self.importState.isWorking == false
    }

    private var primaryButtonTitle: String {
        switch self.importState {
        case .loading:
            return "Validating..."
        case .saving:
            return "Saving..."
        case .saved:
            return "Saved"
        case .idle, .valid, .invalid, .error:
            return "Add RSS Feed"
        }
    }

    private var statusMessage: String? {
        switch self.importState {
        case .idle:
            return nil
        case .loading:
            return "Validating RSS feed..."
        case .valid:
            return "This looks like an RSS feed."
        case .invalid(let message):
            return message
        case .saving:
            return "Saving RSS source..."
        case .saved:
            return "RSS source saved."
        case .error(let message):
            return message
        }
    }

    private var statusForegroundStyle: Color {
        switch self.importState {
        case .invalid, .error:
            return .red
        case .valid, .saved:
            return .green
        case .idle, .loading, .saving:
            return .secondary
        }
    }

    @MainActor
    private func save() async {
        self.importState = .loading

        let recommendation: SourceImportRecommendation = self.validate()
        guard recommendation.isStrongRecommendation else {
            self.importState = .invalid("This URL does not look like an RSS feed. Use a direct .rss, .xml, /rss, or /feed URL.")
            return
        }

        self.importState = .saving
        let source: Source? = await self.viewModel.addRSSSource(
            feedURLString: self.entryURL,
            name: self.trimmedSourceName
        )

        guard source != nil else {
            self.importState = .error(self.viewModel.errorMessage ?? "Failed to save RSS source.")
            return
        }

        self.importState = .saved
        self.completion()
        self.dismiss()
    }

    private func validate() -> SourceImportRecommendation {
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
        return recommendation
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
