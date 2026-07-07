import Foundation
import SwiftUI

// 中文注释：AddSourceView.swift 是中性的添加来源入口，具体导入能力由 SourceImportOption 决定。

struct AddSourceView: View {
    @ObservedObject var viewModel: SourcesViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var isShowingAddRuleSourceView: Bool = false
    @State private var addRuleSourcePresentation: AddRuleSourcePresentation = .comics
    @State private var isShowingImportWebsiteRulePackageView: Bool = false
    @State private var isShowingRSSFeedImportView: Bool = false
    @State private var isShowingVideoSourceImportView: Bool = false
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
                    presentation: self.addRuleSourcePresentation,
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
            .sheet(isPresented: self.$isShowingVideoSourceImportView) {
                VideoSourceImportView(
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
        case .comicSource:
            self.addRuleSourcePresentation = .comics
            self.isShowingAddRuleSourceView = true
        case .videoSource:
            self.isShowingVideoSourceImportView = true
        case .websiteRuleJSON:
            self.addRuleSourcePresentation = .websiteRule
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
            return "Comic sources can be added from the Comics source form."
        case .videoSource:
            return "Video sources can be added from the Video source form."
        case .scriptSource:
            return "Script Source is not available yet."
        case .websiteRuleJSON, .rulePackageJSON, .rssFeedURL, nil:
            return "This source type is not available yet."
        }
    }
}

private struct VideoSourceImportView: View {
    private enum ImportState {
        case idle
        case saving
        case saved
        case needsReview
        case unavailable(VideoSourceUnavailableReason)
        case pluginRequired(VideoSourcePluginReason)
        case error(String)

        var isWorking: Bool {
            switch self {
            case .saving:
                return true
            case .idle, .saved, .needsReview, .unavailable, .pluginRequired, .error:
                return false
            }
        }
    }

    @ObservedObject var viewModel: SourcesViewModel
    let completion: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var entryURL: String = ""
    @State private var sourceName: String = ""
    @State private var importState: ImportState = .idle

    var body: some View {
        NavigationView {
            Form {
                Section("Video Source") {
                    TextField(
                        "Website, detail, or play URL",
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
                        self.primaryAction()
                    }
                    .disabled(self.canSubmit == false)
                }

                Section("Runtime") {
                    LabeledContent("Type", value: "Video")
                    LabeledContent("Template", value: "Auto Detect")
                    Text("RSS URLs should be added from RSS Feed.")
                        .foregroundStyle(.secondary)
                }

                if let message: String = self.statusMessage {
                    Section("Status") {
                        Text(message)
                            .foregroundStyle(self.statusForegroundStyle)
                    }
                }
            }
            .navigationTitle("Video Source")
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
        case .saving:
            return "Saving..."
        case .saved:
            return "Saved"
        case .idle, .unavailable, .pluginRequired, .error:
            return "Add Video Source"
        case .needsReview:
            return "Add Video Source"
        }
    }

    private var statusMessage: String? {
        switch self.importState {
        case .idle:
            return nil
        case .saving:
            return "Saving video source..."
        case .saved:
            return VideoSourceImportStrings.saved
        case .needsReview:
            return VideoSourceImportStrings.needsReview
        case .unavailable(let reason):
            return self.unavailableMessage(reason: reason)
        case .pluginRequired(let reason):
            return self.pluginRequiredMessage(reason: reason)
        case .error(let message):
            return message
        }
    }

    private var statusForegroundStyle: Color {
        switch self.importState {
        case .error, .needsReview, .unavailable, .pluginRequired:
            return .red
        case .saved:
            return .green
        case .idle, .saving:
            return .secondary
        }
    }

    @MainActor
    private func primaryAction() {
        self.startImport()
    }

    @MainActor
    private func startImport() {
        self.importState = .saving
        let result: AddVideoSourceResult? = self.viewModel.addVideoSource(
            entryURLString: self.entryURL,
            name: self.trimmedSourceName
        )

        guard let result: AddVideoSourceResult else {
            self.importState = .error(VideoSourceImportStrings.invalidOrUnavailable)
            return
        }

        self.apply(result)
    }

    @MainActor
    private func apply(_ result: AddVideoSourceResult) {
        switch result {
        case .saved:
            self.finishSaved()
        case .needsReview:
            self.importState = .needsReview
        case .unavailable(let reason):
            self.importState = .unavailable(reason)
        case .pluginRequired(let reason):
            self.importState = .pluginRequired(reason)
        }
    }

    @MainActor
    private func finishSaved() {
        self.importState = .saved
        self.completion()
        self.dismiss()
    }

    private func unavailableMessage(reason: VideoSourceUnavailableReason) -> String {
        return VideoSourceImportResultFormatter.message(for: .unavailable(reason))
    }

    private func pluginRequiredMessage(reason: VideoSourcePluginReason) -> String {
        return VideoSourceImportResultFormatter.message(for: .pluginRequired(reason))
    }
}

enum VideoSourceImportResultFormatter {
    static func message(for result: AddVideoSourceResult) -> String {
        switch result {
        case .saved:
            return VideoSourceImportStrings.saved
        case .needsReview:
            return VideoSourceImportStrings.needsReview
        case .unavailable:
            return VideoSourceImportStrings.unavailable
        case .pluginRequired:
            return VideoSourceImportStrings.pluginRequired
        }
    }
}

enum VideoSourceImportStrings {
    static let saved: String = Self.localized(
        "video_source_import_saved",
        fallback: "Video source saved."
    )
    static let failedToSave: String = Self.localized(
        "video_source_import_failed_to_save",
        fallback: "Failed to save video source."
    )
    static let invalidOrUnavailable: String = Self.localized(
        "video_source_import_invalid_or_unavailable",
        fallback: "This link cannot be added as a video source."
    )
    static let needsReview: String = Self.localized(
        "video_source_import_needs_review",
        fallback: "This website needs further analysis and cannot be added right now."
    )
    static let unavailable: String = Self.localized(
        "video_source_import_unavailable",
        fallback: "This website cannot be loaded as a video source right now."
    )
    static let pluginRequired: String = Self.localized(
        "video_source_import_plugin_required",
        fallback: "This website requires the Plugin module, which is not available yet."
    )

    private static func localized(_ key: String, fallback: String) -> String {
        return NSLocalizedString(
            key,
            tableName: nil,
            bundle: .main,
            value: fallback,
            comment: ""
        )
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
