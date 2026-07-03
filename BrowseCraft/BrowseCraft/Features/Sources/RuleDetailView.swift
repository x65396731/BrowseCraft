import SwiftUI

// 中文注释：RuleDetailView.swift 是 P2-1 的规则详情入口，用于查看、校验和编辑用户规则。

/// 中文注释：RuleDetailView 展示 V2 规则结构摘要，并为用户规则提供 JSON 编辑入口。
struct RuleDetailView: View {
    @ObservedObject var viewModel: SourcesViewModel
    let sourceID: String

    @State private var draftRuleJSON: String = ""
    @State private var draftBasicRule: SiteRule?
    @State private var draftSourceUpdatedAt: Date?
    @State private var validationResult: RuleValidationResult = RuleValidationResult(rule: nil, issues: [])
    @State private var isShowingJSONEditor: Bool = false
    @State private var isShowingBasicEditor: Bool = false

    var body: some View {
        Group {
            if let source: Source = self.viewModel.source(id: self.sourceID) {
                self.content(source: source)
            } else {
                EmptyStateView(
                    systemImage: "questionmark.folder",
                    title: "Source Not Found",
                    message: "The rule may have been deleted."
                )
            }
        }
        .navigationTitle("Rule")
        .onAppear {
            self.resetDraftIfNeeded()
        }
        .sheet(isPresented: self.$isShowingJSONEditor) {
            self.editorSheet()
        }
        .sheet(isPresented: self.$isShowingBasicEditor) {
            self.basicEditorSheet()
        }
    }

    private func content(source: Source) -> some View {
        Form {
            Section("Source") {
                LabeledContent("Name", value: source.name)
                LabeledContent("Base URL", value: source.baseURL)
                LabeledContent("Type", value: source.type.rawValue)
                LabeledContent("Ownership", value: source.isBuiltIn ? "Built-in" : "User")
            }

            self.siteSection(rule: source.rule)
            self.pagesSection(rule: source.rule)
            self.ruleSetsSection(rule: source.rule)
            self.requestSection(rule: source.rule)
            self.jsonPreviewSection(rule: source.rule)

            Section {
                if source.isBuiltIn {
                    Button(
                        action: {
                            _ = self.viewModel.duplicateSource(sourceID: source.id)
                        },
                        label: {
                            Label("Duplicate as User Rule", systemImage: "doc.on.doc")
                        }
                    )
                } else {
                    Button(
                        action: {
                            self.resetDraft(source: source)
                            self.isShowingBasicEditor = true
                        },
                        label: {
                            Label("Edit Basic Fields", systemImage: "list.bullet.rectangle")
                        }
                    )

                    Button(
                        action: {
                            self.resetDraft(source: source)
                            self.isShowingJSONEditor = true
                        },
                        label: {
                            Label("Edit JSON", systemImage: "pencil")
                        }
                    )
                }
            }
        }
    }

    private func siteSection(rule: SiteRule) -> some View {
        Section("Site") {
            LabeledContent("Rule Name", value: rule.name)
            LabeledContent("Base URL", value: rule.baseUrl)

            if let site: SiteConfig = rule.site {
                LabeledContent("Domain", value: site.domain)
                LabeledContent("Display", value: site.displayMode?.rawValue ?? "Default")
                LabeledContent("Language", value: site.language ?? "Unset")
            }
        }
    }

    private func pagesSection(rule: SiteRule) -> some View {
        Section("Pages") {
            let pages: [PageRule] = rule.pages ?? []
            if pages.isEmpty {
                Text("Legacy rule without V2 pages.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(pages) { page in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(page.title)
                            .font(.headline)
                        self.secondaryText("\(page.id) · \(page.type.rawValue)")

                        if let url: String = self.nonEmpty(page.url) {
                            self.keyValueLine("URL", url)
                        }

                        if let displayMode: DisplayMode = page.displayMode {
                            self.keyValueLine("Display", displayMode.rawValue)
                        }

                        let ruleRefs: String = self.ruleRefsSummary(page.ruleRefs)
                        if ruleRefs.isEmpty == false {
                            self.keyValueLine("Rule Refs", ruleRefs)
                        }

                        if let request: RequestConfig = page.request {
                            self.keyValueLine("Request", self.requestSummary(request))
                        }

                        if let tabGroup: TabGroupRule = page.tabGroup {
                            self.keyValueLine("Tabs", "\(tabGroup.tabs.count)")
                        }

                        if let sections: [SectionRule] = page.sections, sections.isEmpty == false {
                            self.keyValueLine("Sections", "\(sections.count)")
                        }
                    }
                }
            }
        }
    }

    private func ruleSetsSection(rule: SiteRule) -> some View {
        Section("RuleSets") {
            let ruleSets: RuleSets? = rule.ruleSets
            self.ruleSetLine("Series", ids: ruleSets?.seriesRules?.compactMap(\.id) ?? [])
            self.ruleSetLine("List", ids: ruleSets?.listRules?.compactMap(\.id) ?? [])
            self.ruleSetLine("Detail", ids: ruleSets?.detailRules?.compactMap(\.id) ?? [])
            self.ruleSetLine("Gallery", ids: ruleSets?.galleryRules?.compactMap(\.id) ?? [])
            self.ruleSetLine("Search", ids: ruleSets?.searchRules?.compactMap(\.id) ?? [])
            LabeledContent("Tabs", value: "\(rule.availableListTabs.count)")
        }
    }

    private func requestSection(rule: SiteRule) -> some View {
        Section("Request") {
            self.requestLine("Shared", request: rule.sharedRequest)
            self.requestLine("List", request: rule.primaryListRequest)
            self.requestLine("Detail", request: rule.primaryDetailRequest)
            self.requestLine("Reader", request: rule.primaryGalleryRequest)
        }
    }

    private func jsonPreviewSection(rule: SiteRule) -> some View {
        Section("JSON Preview") {
            Text(self.viewModel.formattedRuleJSON(for: rule))
                .font(.system(.caption, design: .monospaced))
                .lineLimit(12)
                .textSelection(.enabled)
        }
    }

    private func editorSheet() -> some View {
        NavigationView {
            Form {
                RuleJSONEditorView(
                    ruleJSON: self.$draftRuleJSON,
                    validationResult: self.validationResult,
                    isEditable: true,
                    formatAction: {
                        self.formatDraftJSON()
                    }
                )
            }
            .navigationTitle("Edit Rule JSON")
            .onAppear {
                self.validationResult = self.viewModel.validateRuleJSON(self.draftRuleJSON)
            }
            .onChange(of: self.draftRuleJSON) { _, newValue in
                self.validationResult = self.viewModel.validateRuleJSON(newValue)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        self.isShowingJSONEditor = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if self.viewModel.updateSourceRule(
                            sourceID: self.sourceID,
                            ruleJSON: self.draftRuleJSON,
                            expectedUpdatedAt: self.draftSourceUpdatedAt
                        ) {
                            self.isShowingJSONEditor = false
                        }
                    }
                    .disabled(self.validationResult.canSave == false)
                }
            }
        }
    }

    private func basicEditorSheet() -> some View {
        NavigationView {
            Form {
                if let basicRuleBinding: Binding<SiteRule> = self.draftBasicRuleBinding {
                    RuleBasicFieldsEditorView(rule: basicRuleBinding)
                }
            }
            .navigationTitle("Edit Basic Fields")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        self.isShowingBasicEditor = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if self.saveBasicRule() {
                            self.isShowingBasicEditor = false
                        }
                    }
                    .disabled(self.draftBasicRule == nil)
                }
            }
        }
    }

    private func resetDraftIfNeeded() {
        if self.draftRuleJSON.isEmpty, let source: Source = self.viewModel.source(id: self.sourceID) {
            self.resetDraft(source: source)
        }
    }

    private func resetDraft(source: Source) {
        self.draftRuleJSON = self.viewModel.formattedRuleJSON(for: source.rule)
        self.draftBasicRule = source.rule
        self.draftSourceUpdatedAt = source.updatedAt
        self.validationResult = self.viewModel.validateRuleJSON(self.draftRuleJSON)
    }

    private func formatDraftJSON() {
        guard let rule: SiteRule = self.validationResult.rule else {
            return
        }

        self.draftRuleJSON = self.viewModel.formattedRuleJSON(for: rule)
        self.validationResult = self.viewModel.validateRuleJSON(self.draftRuleJSON)
    }

    private var draftBasicRuleBinding: Binding<SiteRule>? {
        guard self.draftBasicRule != nil else {
            return nil
        }

        return Binding<SiteRule>(
            get: {
                return self.draftBasicRule ?? SiteRule(
                    version: nil,
                    site: nil,
                    urlPatterns: nil,
                    pages: nil,
                    ruleSets: nil,
                    sharedRequest: nil,
                    flags: nil,
                    name: "",
                    baseUrl: "",
                    list: ListRule(
                        id: nil,
                        url: "",
                        text: nil,
                        item: "",
                        itemRule: nil,
                        fields: nil,
                        title: "",
                        link: "",
                        cover: nil,
                        type: .comic,
                        latestText: nil,
                        pagination: nil,
                        ready: nil,
                        request: nil,
                        js: nil
                    ),
                    listTabs: nil,
                    detail: nil,
                    gallery: nil,
                    video: nil
                )
            },
            set: { newValue in
                self.draftBasicRule = newValue
            }
        )
    }

    private func saveBasicRule() -> Bool {
        guard let draftBasicRule: SiteRule = self.draftBasicRule else {
            return false
        }

        let ruleJSON: String = self.viewModel.formattedRuleJSON(for: draftBasicRule)
        return self.viewModel.updateSourceRule(
            sourceID: self.sourceID,
            ruleJSON: ruleJSON,
            expectedUpdatedAt: self.draftSourceUpdatedAt
        )
    }

    private func ruleSetLine(_ title: String, ids: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title, value: "\(ids.count)")
            if ids.isEmpty == false {
                self.secondaryText(ids.joined(separator: ", "))
            }
        }
    }

    private func requestLine(_ title: String, request: RequestConfig?) -> some View {
        LabeledContent(title, value: request.map(self.requestSummary) ?? "Unset")
    }

    private func keyValueLine(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(key)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption)
                .foregroundColor(.secondary)
                .textSelection(.enabled)
        }
    }

    private func secondaryText(_ value: String) -> some View {
        Text(value)
            .font(.caption)
            .foregroundColor(.secondary)
            .textSelection(.enabled)
    }

    private func ruleRefsSummary(_ ruleRefs: RuleRefs?) -> String {
        guard let ruleRefs: RuleRefs = ruleRefs else {
            return ""
        }

        let pairs: [(String, String?)] = [
            ("series", ruleRefs.series),
            ("list", ruleRefs.list),
            ("detail", ruleRefs.detail),
            ("gallery", ruleRefs.gallery),
            ("search", ruleRefs.search)
        ]

        return pairs.compactMap { pair in
            let key: String = pair.0
            let value: String? = pair.1
            guard let value: String = self.nonEmpty(value) else {
                return nil
            }

            return "\(key): \(value)"
        }
        .joined(separator: " · ")
    }

    private func requestSummary(_ request: RequestConfig) -> String {
        var parts: [String] = []

        if let method: HTTPMethod = request.method {
            parts.append(method.rawValue)
        }

        if let scope: RequestScope = request.scope {
            parts.append("scope=\(scope.rawValue)")
        }

        if let mergePolicy: RequestMergePolicy = request.mergePolicy {
            parts.append("merge=\(mergePolicy.rawValue)")
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

        if let cookiePriority: CookiePriority = request.cookiePriority {
            parts.append("cookiePriority=\(cookiePriority.rawValue)")
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

        if let imageRequest: ImageRequestConfig = request.imageRequest {
            let headerCount: Int = imageRequest.headers?.count ?? 0
            parts.append(headerCount > 0 ? "imageRequest headers=\(headerCount)" : "imageRequest")
        }

        if let body: RequestBody = request.body {
            parts.append(body.contentType.map { contentType in
                return "body=\(contentType)"
            } ?? "body")
        }

        return parts.isEmpty ? "Configured" : parts.joined(separator: " · ")
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmedValue: String = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmedValue.isEmpty == false else {
            return nil
        }

        return trimmedValue
    }
}
