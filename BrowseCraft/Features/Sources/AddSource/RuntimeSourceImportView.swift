import Foundation
import SwiftUI
import BrowseCraftCore

// 中文注释：RuntimeSourceImportView 是统一添加源外壳；具体 Debug 由 SourceDebugRouterView 按 runtime 分发。
struct RuntimeSourceImportView: View {
    private enum OperationState: Equatable {
        case idle
        case requesting
        case previewed(RuntimeSourcePreviewResult)
        case saving
        case saved
        case error(String)

        var isWorking: Bool {
            switch self {
            case .requesting, .saving:
                return true
            case .idle, .previewed, .saved, .error:
                return false
            }
        }
    }

    @ObservedObject var viewModel: SourcesViewModel
    let kind: RuntimeSourceImportKind
    let completion: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var entryURL: String = ""
    @State private var sourceName: String = ""
    @State private var ruleJSON: String = ""
    @State private var selectedVideoAdapter: VideoAdapter = .genericHTML
    @State private var selectedVideoEntryKind: VideoSourceEntryKind = .play
    @State private var validationResult: SiteRuleValidationResult = SiteRuleValidationResult(rule: nil, issues: [])
    @State private var operationState: OperationState = .idle
    @State private var isShowingDebugView: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                RuntimeSourceImportInputSection(
                    entryURL: self.$entryURL,
                    sourceName: self.$sourceName,
                    requestButtonTitle: self.requestButtonTitle,
                    isWorking: self.operationState.isWorking,
                    canRequest: self.canRequest,
                    requestAction: self.requestPreviewAction
                )

                if let preview: RuntimeSourcePreviewResult = self.preview {
                    RuntimeSourceImportRequestResultSection(preview: preview)
                }

                RuntimeSourceImportSummarySection(kind: self.kind)

                RuntimeSourceImportDebugEntrySection(
                    canOpenDebug: self.canOpenDebug,
                    openAction: {
                        self.isShowingDebugView = true
                    }
                )

                switch self.kind {
                case .comic:
                    self.comicSections
                case .rss:
                    EmptyView()
                case .video:
                    self.videoSections
                }

                if let message: String = self.statusMessage {
                    Section("Status") {
                        Text(message)
                            .foregroundStyle(self.statusForegroundStyle)
                    }
                }
            }
            .navigationTitle("Add Source")
            .onAppear {
                self.validationResult = self.viewModel.validateRuleJSON(self.ruleJSON)
            }
            .onChange(of: self.ruleJSON) { _, newValue in
                self.validationResult = self.viewModel.validateRuleJSON(newValue)
            }
            .sheet(isPresented: self.$isShowingDebugView) {
                SourceDebugRouterView(
                    viewModel: self.viewModel,
                    kind: self.kind,
                    entryURL: self.entryURL,
                    sourceName: self.trimmedSourceName,
                    videoConfiguration: self.kind == .video ? ManualVideoSourceConfigurationDraft(
                        adapter: self.selectedVideoAdapter,
                        entryKind: self.selectedVideoEntryKind
                    ) : nil,
                    ruleJSON: self.$ruleJSON
                )
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        self.dismiss()
                    }
                    .disabled(self.operationState.isWorking)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await self.save()
                        }
                    }
                    .disabled(self.canSave == false)
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

    private var requestButtonTitle: String {
        switch self.operationState {
        case .requesting:
            return "Requesting..."
        case .previewed:
            return "Request Again"
        case .idle, .saving, .saved, .error:
            return "Request"
        }
    }

    private var canRequest: Bool {
        return self.trimmedEntryURL.isEmpty == false && self.operationState.isWorking == false
    }

    private var canSave: Bool {
        switch self.kind {
        case .comic:
            return self.trimmedEntryURL.isEmpty == false
                && self.validationResult.canSave
                && self.operationState.isWorking == false
        case .rss:
            return self.preview != nil
                && self.trimmedEntryURL.isEmpty == false
                && self.operationState.isWorking == false
        case .video:
            return self.preview != nil
                && self.trimmedEntryURL.isEmpty == false
                && self.selectedVideoAdapter.isManualSaveSupported
                && self.operationState.isWorking == false
        }
    }

    private var canOpenDebug: Bool {
        switch self.kind {
        case .comic:
            return self.operationState.isWorking == false
                && self.trimmedEntryURL.isEmpty == false
        case .rss, .video:
            return self.operationState.isWorking == false
                && self.trimmedEntryURL.isEmpty == false
        }
    }

    private var preview: RuntimeSourcePreviewResult? {
        guard case .previewed(let preview) = self.operationState else {
            return nil
        }

        return preview
    }

    private var statusMessage: String? {
        switch self.operationState {
        case .idle:
            return nil
        case .requesting:
            return "Requesting source..."
        case .previewed:
            return "Request finished."
        case .saving:
            return "Saving source..."
        case .saved:
            return "Source saved."
        case .error(let message):
            return message
        }
    }

    private var statusForegroundStyle: Color {
        switch self.operationState {
        case .error:
            return .red
        case .previewed, .saved:
            return .green
        case .idle, .requesting, .saving:
            return .secondary
        }
    }

    @ViewBuilder
    private var comicSections: some View {
        RuleJSONEditorView(
            ruleJSON: self.$ruleJSON,
            validationResult: self.validationResult,
            isEditable: self.operationState.isWorking == false,
            formatAction: {
                self.formatRuleJSON()
            }
        )
    }

    @ViewBuilder
    private var videoSections: some View {
        Section("Manual Rule") {
            Picker("Adapter", selection: self.$selectedVideoAdapter) {
                ForEach(VideoAdapter.manualImportOptions, id: \.self) { adapter in
                    Text(adapter.manualImportTitle)
                        .tag(adapter)
                }
            }

            Picker("Entry", selection: self.$selectedVideoEntryKind) {
                ForEach(VideoSourceEntryKind.manualImportOptions, id: \.self) { entryKind in
                    Text(entryKind.manualImportTitle)
                        .tag(entryKind)
                }
            }

            Text(self.manualVideoRuleSummary)
                .foregroundStyle(.secondary)
        }
    }

    private func requestPreviewAction() {
        Task {
            await self.requestPreview()
        }
    }

    @MainActor
    private func requestPreview() async {
        self.operationState = .requesting
        let preview: RuntimeSourcePreviewResult? = await self.viewModel.previewRuntimeSource(
            kind: self.kind,
            entryURLString: self.entryURL,
            name: self.trimmedSourceName
        )

        guard let preview: RuntimeSourcePreviewResult else {
            self.operationState = .error(self.viewModel.errorMessage ?? "Failed to request source.")
            return
        }

        self.applyComicRuleDraftIfNeeded(from: preview)
        self.operationState = .previewed(preview)
    }

    @MainActor
    private func save() async {
        self.operationState = .saving

        switch self.kind {
        case .comic:
            await self.saveComic()
        case .rss:
            await self.saveRSS()
        case .video:
            await self.saveVideo()
        }
    }

    @MainActor
    private func saveComic() async {
        let didSave: Bool = await self.viewModel.addRuleSource(
            name: self.trimmedSourceName ?? "",
            baseURL: self.trimmedEntryURL,
            ruleJSON: self.ruleJSON
        )

        guard didSave else {
            self.operationState = .error(self.viewModel.errorMessage ?? "Failed to save comic source.")
            return
        }

        self.finishSaved()
    }

    @MainActor
    private func saveRSS() async {
        let source: Source? = await self.viewModel.addRSSSource(
            feedURLString: self.entryURL,
            name: self.trimmedSourceName
        )

        guard source != nil else {
            self.operationState = .error(self.viewModel.errorMessage ?? "Failed to save RSS source.")
            return
        }

        self.finishSaved()
    }

    @MainActor
    private func saveVideo() async {
        let source: Source? = await self.viewModel.addManualVideoSource(
            entryURLString: self.entryURL,
            name: self.trimmedSourceName,
            configuration: ManualVideoSourceConfigurationDraft(
                adapter: self.selectedVideoAdapter,
                entryKind: self.selectedVideoEntryKind
            )
        )

        guard source != nil else {
            self.operationState = .error(self.viewModel.errorMessage ?? "Failed to save video source.")
            return
        }

        self.finishSaved()
    }

    @MainActor
    private func finishSaved() {
        self.operationState = .saved
        self.completion()
        self.dismiss()
    }

    private func formatRuleJSON() {
        guard let rule: SiteRule = self.validationResult.rule else {
            return
        }

        self.ruleJSON = self.viewModel.formattedRuleJSON(for: rule)
        self.validationResult = self.viewModel.validateRuleJSON(self.ruleJSON)
    }

    private func applyComicRuleDraftIfNeeded(from preview: RuntimeSourcePreviewResult) {
        guard self.kind == .comic,
              self.ruleJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        self.ruleJSON = Self.makeComicRuleDraftJSON(from: preview)
        self.validationResult = self.viewModel.validateRuleJSON(self.ruleJSON)
    }

    private static func makeComicRuleDraftJSON(from preview: RuntimeSourcePreviewResult) -> String {
        let baseURL: String = preview.entryURL.absoluteString
        let trimmedTitle: String? = preview.title?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceName: String
        if let trimmedTitle: String, trimmedTitle.isEmpty == false {
            sourceName = trimmedTitle
        } else {
            sourceName = preview.entryURL.host ?? "Comic Source"
        }
        let draft: [String: Any] = [
            "name": sourceName,
            "baseUrl": baseURL,
            "list": [
                "url": baseURL,
                "item": ".comic-item",
                "title": ".title",
                "link": "a@href",
                "cover": "img@data-src|src",
                "type": "comic",
                "latestText": ".latest"
            ],
            "detail": [
                "title": "h1",
                "cover": ".cover img@data-src|src",
                "chapterContainer": ".chapter-list",
                "chapterItem": ".chapter-list a",
                "chapterTitle": "this",
                "chapterLink": "this@href"
            ],
            "gallery": [
                "imageItem": ".reader img",
                "imageUrl": "this@data-src|src"
            ]
        ]

        guard JSONSerialization.isValidJSONObject(draft),
              let data: Data = try? JSONSerialization.data(
                withJSONObject: draft,
                options: [.prettyPrinted, .sortedKeys]
              ),
              let json: String = String(data: data, encoding: .utf8) else {
            return SiteRule.exampleJSON
        }

        return json
    }

    private var manualVideoRuleSummary: String {
        if self.selectedVideoEntryKind == .play {
            return "Use Play for direct player URLs. Embed URLs are handled as iframePlayer/pageOnly unless the page exposes mp4 or m3u8."
        }

        return "Use Home/List/Detail only when the URL represents a browsable video page."
    }
}

private extension VideoAdapter {
    static var manualImportOptions: [VideoAdapter] {
        return [.genericHTML, .macCMS, .webView, .plugin]
    }

    var manualImportTitle: String {
        switch self {
        case .genericHTML:
            return "Generic HTML"
        case .macCMS:
            return "MacCMS"
        case .webView:
            return "WebView"
        case .plugin:
            return "Plugin"
        }
    }

    var isManualSaveSupported: Bool {
        switch self {
        case .genericHTML, .macCMS:
            return true
        case .webView, .plugin:
            return false
        }
    }
}

private extension VideoSourceEntryKind {
    static var manualImportOptions: [VideoSourceEntryKind] {
        return [.play, .home, .list, .detail, .category]
    }

    var manualImportTitle: String {
        switch self {
        case .home:
            return "Home"
        case .category:
            return "Category"
        case .list:
            return "List"
        case .detail:
            return "Detail"
        case .play:
            return "Play"
        }
    }
}
