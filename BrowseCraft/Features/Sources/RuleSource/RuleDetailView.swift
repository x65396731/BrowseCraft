import SwiftUI
import BrowseCraftCore

// 中文注释：SourceDebugView 是统一调试入口；漫画和视频可编辑 JSON，RSS/插件保持只读。

struct SourceDebugView: View {
    @ObservedObject var viewModel: SourcesViewModel
    let sourceID: String

    @State private var draftJSON: String = ""
    @State private var draftSourceUpdatedAt: Date?
    @State private var validationResult: SourceDebugJSONValidationResult = SourceDebugJSONValidationResult(
        isValid: false,
        message: ""
    )
    @State private var isShowingJSONEditor: Bool = false

    var body: some View {
        Group {
            if let source: Source = self.viewModel.source(id: self.sourceID) {
                self.content(source: source)
            } else {
                EmptyStateView(
                    systemImage: "questionmark.folder",
                    title: "Source Not Found",
                    message: "The source may have been deleted."
                )
            }
        }
        .navigationTitle("Debug")
        .onAppear {
            CrashDiagnostics.shared.setScreen(.ruleEditor)
            AppAnalytics.shared.logScreenView(.ruleEditor)
            CrashDiagnostics.shared.setSource(self.viewModel.source(id: self.sourceID))
            self.resetDraftIfNeeded()
        }
        .sheet(isPresented: self.$isShowingJSONEditor) {
            self.editorSheet()
        }
    }

    private func content(source: Source) -> some View {
        Form {
            self.sourceSection(source: source)

            switch source.configuration {
            case .comic(let configuration):
                self.comicSection(rule: configuration.rule)
                self.comicRuleSetsSection(rule: configuration.rule)
                self.comicRequestSection(rule: configuration.rule)
            case .video(let configuration):
                self.videoSection(configuration: configuration)
            case .rss(let configuration):
                self.rssSection(configuration: configuration)
            case .plugin(let configuration):
                self.pluginSection(configuration: configuration)
            }

            self.jsonPreviewSection(source: source)

            Section {
                if self.viewModel.canEditDebugJSON(for: source) {
                    Button(
                        action: {
                            self.resetDraft(source: source)
                            self.isShowingJSONEditor = true
                        },
                        label: {
                            Label("Edit JSON", systemImage: "pencil")
                        }
                    )
                } else {
                    Label(
                        source.isBuiltIn ? "Built-in source JSON is read-only." : "This source JSON is read-only.",
                        systemImage: "lock"
                    )
                    .foregroundColor(.secondary)
                }
            }
        }
    }

    private func sourceSection(source: Source) -> some View {
        Section("Source") {
            LabeledContent("Name", value: source.name)
            LabeledContent("Base URL", value: source.baseURL)
            LabeledContent("Runtime", value: self.runtimeTitle(for: source))
            LabeledContent("Type", value: source.type.rawValue)
            LabeledContent("Ownership", value: source.isBuiltIn ? "Built-in" : "User")
        }
    }

    private func comicSection(rule: SiteRule) -> some View {
        Section("Comic Rule") {
            LabeledContent("Rule Name", value: rule.name)
            LabeledContent("Base URL", value: rule.baseUrl)

            if let site: SiteConfig = rule.site {
                LabeledContent("Domain", value: site.domain)
                LabeledContent("Display", value: site.displayMode?.rawValue ?? "Default")
                LabeledContent("Language", value: site.language ?? "Unset")
            }

            LabeledContent("Pages", value: "\(rule.pages?.count ?? 0)")
            LabeledContent("Tabs", value: "\(rule.availableListTabs.count)")
        }
    }

    private func comicRuleSetsSection(rule: SiteRule) -> some View {
        Section("RuleSets") {
            let ruleSets: RuleSets? = rule.ruleSets
            self.countLine("Series", count: ruleSets?.seriesRules?.count ?? 0)
            self.countLine("List", count: ruleSets?.listRules?.count ?? 0)
            self.countLine("Detail", count: ruleSets?.detailRules?.count ?? 0)
            self.countLine("Gallery", count: ruleSets?.galleryRules?.count ?? 0)
            self.countLine("Search", count: ruleSets?.searchRules?.count ?? 0)
        }
    }

    private func comicRequestSection(rule: SiteRule) -> some View {
        let resolvedRule: ResolvedSiteRule = RuleResolver().resolve(rule)

        return Section("Request") {
            self.requestLine("Shared", request: rule.sharedRequest)
            self.requestLine("List", request: rule.primaryListRequest)
            self.requestLine("Detail", request: resolvedRule.primaryDetailRequest)
            self.requestLine("Reader", request: resolvedRule.primaryGalleryRequest)
        }
    }

    private func videoSection(configuration: VideoSourceConfiguration) -> some View {
        Section("Video") {
            let definition: VideoSourceDefinition = configuration.definition
            LabeledContent("Adapter", value: definition.adapter.rawValue)
            LabeledContent("Entry URL", value: definition.entryURL.absoluteString)
            LabeledContent("Entry Kind", value: definition.entryKind.rawValue)
            LabeledContent("Playback", value: definition.playbackPolicy.rawValue)
            LabeledContent("Requires Account", value: definition.requiresAccount ? "Yes" : "No")
            LabeledContent("Tabs", value: "\(configuration.listTabs.count)")

            if let seedURL: URL = definition.seedURL {
                LabeledContent("Seed URL", value: seedURL.absoluteString)
            }

            if let seedPlayURL: URL = definition.seedPlayURL {
                LabeledContent("Seed Play URL", value: seedPlayURL.absoluteString)
            }

            self.requestLine("Shared Request", request: definition.sharedRequest)
            self.requestLine("List Request", request: definition.listRequest)
            self.requestLine("Detail Request", request: definition.detailRequest)
            self.requestLine("Play Request", request: definition.playRequest)
        }
    }

    private func rssSection(configuration: RSSSourceConfiguration) -> some View {
        Section("RSS") {
            LabeledContent("Feed URL", value: configuration.definition.feedURL.absoluteString)
            LabeledContent("Refresh", value: configuration.definition.refreshPolicy.rawValue)
            LabeledContent("Requires Account", value: configuration.definition.requiresAccount ? "Yes" : "No")
        }
    }

    private func pluginSection(configuration: PluginSourceConfiguration) -> some View {
        Section("Plugin") {
            LabeledContent("Plugin ID", value: configuration.definition.id)
            LabeledContent("Display Name", value: configuration.definition.displayName)
            LabeledContent("Runtime", value: configuration.definition.runtime.rawValue)
            LabeledContent("Entrypoint", value: configuration.definition.entrypoint)
        }
    }

    private func jsonPreviewSection(source: Source) -> some View {
        Section("JSON Preview") {
            Text(self.viewModel.formattedDebugJSON(for: source))
                .font(.system(.caption, design: .monospaced))
                .lineLimit(12)
                .textSelection(.enabled)
        }
    }

    private func editorSheet() -> some View {
        NavigationStack {
            Form {
                Section("JSON") {
                    Label(
                        self.validationResult.message,
                        systemImage: self.validationResult.isValid ? "checkmark.circle.fill" : "xmark.octagon.fill"
                    )
                    .foregroundColor(self.validationResult.isValid ? .green : .red)

                    TextEditor(text: self.$draftJSON)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 360)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Edit JSON")
            .onAppear {
                self.validateDraftJSON()
            }
            .onChange(of: self.draftJSON) { _, _ in
                self.validateDraftJSON()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        self.isShowingJSONEditor = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if self.viewModel.updateDebugJSON(
                            sourceID: self.sourceID,
                            json: self.draftJSON,
                            expectedUpdatedAt: self.draftSourceUpdatedAt
                        ) {
                            self.isShowingJSONEditor = false
                        }
                    }
                    .disabled(self.validationResult.isValid == false)
                }
            }
        }
    }

    private func resetDraftIfNeeded() {
        if self.draftJSON.isEmpty, let source: Source = self.viewModel.source(id: self.sourceID) {
            self.resetDraft(source: source)
        }
    }

    private func resetDraft(source: Source) {
        self.draftJSON = self.viewModel.formattedDebugJSON(for: source)
        self.draftSourceUpdatedAt = source.updatedAt
        self.validateDraftJSON()
    }

    private func validateDraftJSON() {
        self.validationResult = self.viewModel.validateDebugJSON(
            sourceID: self.sourceID,
            json: self.draftJSON
        )
    }

    private func runtimeTitle(for source: Source) -> String {
        switch source.configuration {
        case .comic:
            return "Comic"
        case .video:
            return "Video"
        case .rss:
            return "RSS"
        case .plugin:
            return "Plugin"
        }
    }

    private func countLine(_ title: String, count: Int) -> some View {
        LabeledContent(title, value: "\(count)")
    }

    private func requestLine(_ title: String, request: RequestConfig?) -> some View {
        LabeledContent(title, value: request.map(self.requestSummary) ?? "Unset")
    }

    private func requestSummary(_ request: RequestConfig) -> String {
        var parts: [String] = []

        if let method: HTTPMethod = request.method {
            parts.append(method.rawValue)
        }

        if request.needsWebView == true {
            parts.append("WebView")
        }

        if request.autoScroll == true {
            parts.append("auto-scroll")
        }

        if let cookiePolicy: CookiePolicy = request.cookiePolicy {
            parts.append("cookie=\(cookiePolicy.rawValue)")
        }

        if let charset: Charset = request.charset {
            parts.append("charset=\(charset.rawValue)")
        }

        if let headers: [String: String] = request.headers, headers.isEmpty == false {
            parts.append("headers=\(headers.count)")
        }

        if let imageHeaders: [String: String] = request.imageHeaders, imageHeaders.isEmpty == false {
            parts.append("imageHeaders=\(imageHeaders.count)")
        }

        return parts.isEmpty ? "Configured" : parts.joined(separator: " · ")
    }
}
