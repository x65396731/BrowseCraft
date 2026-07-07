import SwiftUI
import UIKit

// 中文注释：RuleDetailView.swift 是 P2-1 的规则详情入口，用于查看、校验和编辑用户规则。

/// 中文注释：RuleDetailView 展示 V2 规则结构摘要，并为用户规则提供 JSON 编辑入口。
struct RuleDetailView: View {
    @ObservedObject var viewModel: SourcesViewModel
    let sourceID: String
    private let candidateDraftApplier: RuleCandidateDraftApplier = RuleCandidateDraftApplier()

    @State private var draftRuleJSON: String = ""
    @State private var draftBasicRule: SiteRule?
    @State private var draftSourceUpdatedAt: Date?
    @State private var validationResult: SiteRuleValidationResult = SiteRuleValidationResult(rule: nil, issues: [])
    @State private var isShowingJSONEditor: Bool = false
    @State private var isShowingBasicEditor: Bool = false
    @State private var exportedPackage: RulePackageExport?
    @State private var isShowingExportSheet: Bool = false
    @State private var didCopyExport: Bool = false
    @State private var debugSession: RuleDebugSession?
    @State private var isShowingDebugSheet: Bool = false
    @State private var isRunningListDebug: Bool = false
    @State private var isRunningSearchDebug: Bool = false
    @State private var isRunningDetailDebug: Bool = false
    @State private var isRunningReaderDebug: Bool = false
    @State private var debugKeywordText: String = ""
    @State private var debugPageText: String = "1"
    @State private var debugURLOverride: String = ""
    @State private var didCopyDebugSummary: Bool = false
    @State private var didApplyCandidateDraft: Bool = false

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
        .sheet(isPresented: self.$isShowingExportSheet) {
            self.exportSheet()
        }
        .sheet(isPresented: self.$isShowingDebugSheet) {
            self.debugSheet()
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
            self.rulePackageSection(source: source)
            self.debugSection(source: source)

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

    private func rulePackageSection(source: Source) -> some View {
        Section("Rule Package") {
            Button(
                action: {
                    self.exportRulePackage(sourceID: source.id)
                },
                label: {
                    Label("Export Rule Package", systemImage: "square.and.arrow.up")
                }
            )
        }
    }

    private func debugSection(source: Source) -> some View {
        Section("Rule Debug") {
            TextField("Keyword", text: self.$debugKeywordText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Stepper(
                value: self.debugPageBinding,
                in: 1...999
            ) {
                LabeledContent("Page", value: "\(self.debugPage)")
            }

            TextField("URL override", text: self.$debugURLOverride)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if self.hasSearchRule(source: source) {
                Button(
                    action: {
                        self.runSearchDebug(source: source)
                    },
                    label: {
                        Label("Debug Search", systemImage: "magnifyingglass")
                    }
                )
                .disabled(self.isRunningDebug || self.nonEmpty(self.debugKeywordText) == nil)
            }

            ForEach(source.rule.availableListTabs) { listTab in
                Button(
                    action: {
                        self.runListDebug(source: source, listTab: listTab)
                    },
                    label: {
                        Label("Debug \(listTab.title)", systemImage: "ladybug")
                    }
                )
                .disabled(self.isRunningDebug)
            }

            if self.isRunningDebug {
                HStack {
                    ProgressView()
                    Text(self.debugProgressText)
                        .foregroundColor(.secondary)
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
        let resolvedRule: ResolvedSiteRule = RuleResolver().resolve(rule)

        return Section("Request") {
            self.requestLine("Shared", request: rule.sharedRequest)
            self.requestLine("List", request: rule.primaryListRequest)
            self.requestLine("Detail", request: resolvedRule.primaryDetailRequest)
            self.requestLine("Reader", request: resolvedRule.primaryGalleryRequest)
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
        NavigationStack {
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
        NavigationStack {
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

    private func exportSheet() -> some View {
        NavigationStack {
            Form {
                if let exportedPackage: RulePackageExport = self.exportedPackage {
                    Section("File") {
                        LabeledContent("Name", value: exportedPackage.suggestedFileName)
                        ShareLink(item: exportedPackage.packageJSON) {
                            Label("Share Package JSON", systemImage: "square.and.arrow.up")
                        }
                    }

                    Section("Package JSON") {
                        Text(exportedPackage.packageJSON)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                } else {
                    EmptyStateView(
                        systemImage: "exclamationmark.triangle",
                        title: "Export Failed",
                        message: "The rule package could not be generated."
                    )
                }
            }
            .navigationTitle("Export Rule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        self.isShowingExportSheet = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(
                        action: {
                            self.copyExportedPackage()
                        },
                        label: {
                            Label(
                                self.didCopyExport ? "Copied" : "Copy",
                                systemImage: self.didCopyExport ? "checkmark" : "doc.on.doc"
                            )
                        }
                    )
                    .disabled(self.exportedPackage == nil)
                }
            }
        }
    }

    private func debugSheet() -> some View {
        NavigationStack {
            RuleDebugSessionView(
                session: self.debugSession,
                applyCandidate: { candidate in
                    self.applyCandidateToDraft(candidate)
                },
                canApplyCandidate: { candidate in
                    self.canApplyCandidateToDraft(candidate)
                },
                debugDetail: { item, context in
                    guard let source: Source = self.viewModel.source(id: self.sourceID) else {
                        return
                    }

                    self.runDetailDebug(source: source, item: item, context: context)
                },
                debugReader: { item, context in
                    guard let source: Source = self.viewModel.source(id: self.sourceID) else {
                        return
                    }

                    self.runReaderDebug(source: source, item: item, context: context)
                }
            )
                .navigationTitle(self.debugSheetTitle)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            self.isShowingDebugSheet = false
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button(
                            action: {
                                self.copyDebugSummary()
                            },
                            label: {
                                Label(
                                    self.didCopyDebugSummary ? "Copied" : "Copy Summary",
                                    systemImage: self.didCopyDebugSummary ? "checkmark" : "doc.on.doc"
                                )
                            }
                        )
                        .disabled(self.debugSession == nil)
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

    private func exportRulePackage(sourceID: String) {
        self.didCopyExport = false

        guard let exportedPackage: RulePackageExport = self.viewModel.exportRulePackage(sourceID: sourceID) else {
            return
        }

        self.exportedPackage = exportedPackage
        self.isShowingExportSheet = true
    }

    private func copyExportedPackage() {
        guard let exportedPackage: RulePackageExport = self.exportedPackage else {
            return
        }

        UIPasteboard.general.string = exportedPackage.packageJSON
        self.didCopyExport = true
    }

    private func runListDebug(source: Source, listTab: ListTabRule) {
        if self.isRunningDebug {
            return
        }

        self.isRunningListDebug = true
        let page: Int = self.debugPage
        let urlOverride: String? = self.nonEmpty(self.debugURLOverride)

        Task {
            let session: RuleDebugSession = await self.viewModel.debugListRule(
                source: source,
                listTab: listTab,
                page: page,
                urlOverride: urlOverride
            )

            await MainActor.run {
                self.debugSession = session
                self.didCopyDebugSummary = false
                self.didApplyCandidateDraft = false
                self.isRunningListDebug = false
                self.isShowingDebugSheet = true
            }
        }
    }

    private func runSearchDebug(source: Source) {
        if self.isRunningDebug {
            return
        }

        guard let keyword: String = self.nonEmpty(self.debugKeywordText) else {
            return
        }

        self.isRunningSearchDebug = true
        let page: Int = self.debugPage
        let urlOverride: String? = self.nonEmpty(self.debugURLOverride)

        Task {
            let session: RuleDebugSession = await self.viewModel.debugSearchRule(
                source: source,
                keyword: keyword,
                page: page,
                urlOverride: urlOverride
            )

            await MainActor.run {
                self.debugSession = session
                self.didCopyDebugSummary = false
                self.didApplyCandidateDraft = false
                self.isRunningSearchDebug = false
                self.isShowingDebugSheet = true
            }
        }
    }

    private func runDetailDebug(source: Source, item: RuleDebugPreviewItem, context: ListContext?) {
        if self.isRunningDebug {
            return
        }

        guard let detailURL: String = self.nonEmpty(item.detailURL) else {
            return
        }

        self.isRunningDetailDebug = true

        Task {
            let session: RuleDebugSession = await self.viewModel.debugDetailRule(
                source: source,
                detailURL: detailURL,
                context: context
            )

            await MainActor.run {
                self.debugSession = session
                self.didCopyDebugSummary = false
                self.didApplyCandidateDraft = false
                self.isRunningDetailDebug = false
                self.isShowingDebugSheet = true
            }
        }
    }

    private func runReaderDebug(source: Source, item: RuleDebugPreviewItem, context: ListContext?) {
        if self.isRunningDebug {
            return
        }

        guard let chapterURL: String = self.nonEmpty(item.chapterURL) else {
            return
        }

        self.isRunningReaderDebug = true

        Task {
            let session: RuleDebugSession = await self.viewModel.debugReaderRule(
                source: source,
                chapterURL: chapterURL,
                context: context
            )

            await MainActor.run {
                self.debugSession = session
                self.didCopyDebugSummary = false
                self.didApplyCandidateDraft = false
                self.isRunningReaderDebug = false
                self.isShowingDebugSheet = true
            }
        }
    }

    private func copyDebugSummary() {
        guard let debugSession: RuleDebugSession = self.debugSession else {
            return
        }

        UIPasteboard.general.string = self.debugSummaryMarkdown(session: debugSession)
        self.didCopyDebugSummary = true
    }

    private func debugSummaryMarkdown(session: RuleDebugSession) -> String {
        var lines: [String] = [
            "# Rule Debug Summary",
            "",
            "## Diagnosis",
            "- Status: \(session.status.rawValue)",
            "- Stage: \(session.input.stage.rawValue)",
            "- Source: \(session.input.sourceName)",
            "- Source ID: \(session.input.sourceID)",
            "- Rule ID: \(session.input.ruleID ?? "Default")"
        ]

        if let keyword: String = session.input.keyword {
            lines.append("- Keyword: \(keyword)")
        }

        if let tabID: String = session.input.tabID {
            lines.append("- Tab ID: \(tabID)")
        }

        if let page: Int = session.input.page {
            lines.append("- Page: \(page)")
        }

        if let urlOverride: String = session.input.url {
            lines.append("- URL Override: \(urlOverride)")
        }

        lines.append("")
        lines.append("## Issues")

        if session.issues.isEmpty {
            lines.append("- None")
        } else {
            for issue: RuleDebugIssue in session.issues {
                let fieldText: String = issue.field.map { field in " field=\(field.rawValue)" } ?? ""
                lines.append(
                    "- \(issue.severity.rawValue) \(issue.category.rawValue)\(fieldText): \(issue.message)"
                )
            }
        }

        lines.append("")
        lines.append("## Request")

        if session.requestLogs.isEmpty {
            lines.append("- No request was sent.")
        } else {
            for log: RuleDebugRequestLog in session.requestLogs {
                lines.append("- URL: \(log.url)")
                lines.append("  - Method: \(log.method)")
                lines.append("  - Headers: \(log.requestSummary.headerCount)")
                lines.append("  - WebView: \(log.requestSummary.needsWebView ? "yes" : "no")")
                lines.append("  - Auto Scroll: \(log.requestSummary.autoScroll ? "yes" : "no")")

                if let contentLength: Int = log.responseSummary?.contentLength {
                    lines.append("  - Content Length: \(contentLength)")
                }

                if let errorMessage: String = log.errorMessage {
                    lines.append("  - Error: \(errorMessage)")
                }
            }
        }

        lines.append("")
        lines.append("## Extraction")

        if session.extractionLogs.isEmpty {
            lines.append("- No extraction logs.")
        } else {
            for log: RuleDebugExtractionLog in session.extractionLogs {
                lines.append("- Field: \(log.field?.rawValue ?? "unknown")")
                lines.append("  - Selector: \(log.selector ?? "none")")
                lines.append("  - Candidates: \(log.candidateCount.map { count in "\(count)" } ?? "unknown")")
                lines.append("  - Output: \(log.outputCount.map { count in "\(count)" } ?? "unknown")")

                if log.samples.isEmpty == false {
                    lines.append("  - Samples: \(log.samples.prefix(3).joined(separator: " | "))")
                }
            }
        }

        lines.append("")
        lines.append("## Pagination")

        if let pagination: PaginationResolution = session.pagination {
            lines.append("- Current Page: \(pagination.currentPage)")
            lines.append("- Next Page: \(pagination.nextPage.map { page in "\(page)" } ?? "None")")
            lines.append("- Next URL: \(pagination.nextURL ?? "None")")
            lines.append("- Source: \(pagination.source?.rawValue ?? "None")")
        } else {
            lines.append("- None")
        }

        lines.append("")
        lines.append("## Candidate Recommendations")

        if let report: RuleCandidateReport = session.candidateReport,
           report.candidates.isEmpty == false {
            for candidate: RuleCandidate in report.candidates.prefix(10) {
                lines.append("- \(candidate.field.rawValue): \(candidate.selector)")
                lines.append("  - Function: \(candidate.function.rawValue)")
                lines.append("  - Param: \(candidate.param ?? "None")")
                lines.append("  - Confidence: \(candidate.score.confidence.rawValue)")

                if candidate.evidence.sampleValues.isEmpty == false {
                    lines.append("  - Samples: \(candidate.evidence.sampleValues.prefix(3).joined(separator: " | "))")
                }
            }
        } else {
            lines.append("- None")
        }

        lines.append("")
        lines.append("## Preview")

        if session.previewItems.isEmpty {
            lines.append("- No preview items.")
        } else {
            for item: RuleDebugPreviewItem in session.previewItems.prefix(10) {
                lines.append("- \(item.title)")

                if let detailURL: String = item.detailURL {
                    lines.append("  - Detail: \(detailURL)")
                }

                if let coverURL: String = item.coverURL {
                    lines.append("  - Cover: \(coverURL)")
                }

                if let latestText: String = item.latestText {
                    lines.append("  - Latest: \(latestText)")
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    private func applyCandidateToDraft(_ candidate: RuleCandidate) {
        guard let source: Source = self.viewModel.source(id: self.sourceID),
              source.isBuiltIn == false else {
            UIPasteboard.general.string = self.candidateRuleSnippet(candidate)
            return
        }

        self.resetDraft(source: source)

        guard var rule: SiteRule = self.draftBasicRule else {
            return
        }

        let didApply: Bool = self.candidateDraftApplier.apply(
            candidate: candidate,
            stage: self.debugSession?.input.stage,
            ruleID: self.debugSession?.input.ruleID,
            rule: &rule
        )

        guard didApply else {
            UIPasteboard.general.string = self.candidateRuleSnippet(candidate)
            self.didApplyCandidateDraft = false
            return
        }

        self.draftBasicRule = rule
        self.draftRuleJSON = self.viewModel.formattedRuleJSON(for: rule)
        self.validationResult = self.viewModel.validateRuleJSON(self.draftRuleJSON)
        UIPasteboard.general.string = self.candidateRuleSnippet(candidate)
        self.didApplyCandidateDraft = true
        self.isShowingDebugSheet = false
        self.isShowingJSONEditor = true
    }

    private func canApplyCandidateToDraft(_ candidate: RuleCandidate) -> Bool {
        guard let source: Source = self.viewModel.source(id: self.sourceID),
              source.isBuiltIn == false else {
            return false
        }

        return self.candidateDraftApplier.canApply(
            candidate: candidate,
            stage: self.debugSession?.input.stage
        )
    }

    private func candidateRuleSnippet(_ candidate: RuleCandidate) -> String {
        var lines: [String] = [
            "{",
            "  \"field\": \"\(candidate.field.rawValue)\",",
            "  \"selector\": \"\(self.escapeJSON(candidate.selector))\",",
            "  \"selectorKind\": \"\(candidate.selectorKind.rawValue)\",",
            "  \"function\": \"\(candidate.function.rawValue)\""
        ]

        if let param: String = candidate.param {
            lines[lines.count - 1] += ","
            lines.append("  \"param\": \"\(self.escapeJSON(param))\"")
        }

        lines.append("}")
        return lines.joined(separator: "\n")
    }

    private func escapeJSON(_ value: String) -> String {
        return value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private var isRunningDebug: Bool {
        return self.isRunningListDebug ||
            self.isRunningSearchDebug ||
            self.isRunningDetailDebug ||
            self.isRunningReaderDebug
    }

    private var debugProgressText: String {
        if self.isRunningSearchDebug {
            return "Debugging search rule..."
        }

        if self.isRunningDetailDebug {
            return "Debugging detail rule..."
        }

        if self.isRunningReaderDebug {
            return "Debugging reader rule..."
        }

        return "Debugging list rule..."
    }

    private var debugSheetTitle: String {
        switch self.debugSession?.input.stage {
        case .search:
            return "Search Debug"
        case .list:
            return "List Debug"
        case .detail:
            return "Detail Debug"
        case .reader:
            return "Reader Debug"
        case nil:
            return "Rule Debug"
        }
    }

    private func hasSearchRule(source: Source) -> Bool {
        return source.rule.ruleSets?.searchRules?.isEmpty == false
    }

    private var debugPage: Int {
        guard let page: Int = Int(self.debugPageText),
              page > 0 else {
            return 1
        }

        return page
    }

    private var debugPageBinding: Binding<Int> {
        return Binding<Int>(
            get: {
                return self.debugPage
            },
            set: { newValue in
                self.debugPageText = "\(max(1, newValue))"
            }
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

private struct RuleDebugSessionView: View {
    let session: RuleDebugSession?
    let applyCandidate: (RuleCandidate) -> Void
    let canApplyCandidate: (RuleCandidate) -> Bool
    let debugDetail: (RuleDebugPreviewItem, ListContext?) -> Void
    let debugReader: (RuleDebugPreviewItem, ListContext?) -> Void

    var body: some View {
        Form {
            if let session: RuleDebugSession = self.session {
                self.diagnosisSection(session: session)
                self.requestSection(session.requestLogs)
                self.extractionSection(session.extractionLogs)
                self.paginationSection(session.pagination)
                self.candidateSection(session.candidateReport)
                self.previewSection(session: session)
            } else {
                EmptyStateView(
                    systemImage: "ladybug",
                    title: "No Debug Session",
                    message: "Run a rule debug first."
                )
            }
        }
    }

    private func candidateSection(_ report: RuleCandidateReport?) -> some View {
        Section("Candidate Recommendations") {
            if let report: RuleCandidateReport = report,
               report.candidates.isEmpty == false {
                LabeledContent("Candidates", value: "\(report.summary.candidateCount)")
                LabeledContent("High Confidence", value: "\(report.summary.highConfidenceCount)")
                LabeledContent("Warnings", value: "\(report.summary.warningCount)")

                ForEach(report.candidates) { candidate in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(candidate.field.rawValue)
                                .font(.headline)
                            Spacer()
                            Text(candidate.score.confidence.rawValue)
                                .font(.caption)
                                .foregroundColor(self.confidenceColor(candidate.score.confidence))
                        }

                        self.keyValueLine("Selector", candidate.selector)
                        self.keyValueLine("Function", candidate.function.rawValue)

                        if let param: String = candidate.param {
                            self.keyValueLine("Param", param)
                        }

                        if candidate.evidence.sampleValues.isEmpty == false {
                            self.keyValueLine("Samples", candidate.evidence.sampleValues.prefix(3).joined(separator: " · "))
                        }

                        if candidate.score.reasons.isEmpty == false {
                            self.secondaryText(candidate.score.reasons.joined(separator: " · "))
                        }

                        if candidate.warnings.isEmpty == false {
                            ForEach(candidate.warnings) { warning in
                                Text("\(warning.severity.rawValue) · \(warning.message)")
                                    .font(.caption)
                                    .foregroundColor(warning.severity == .error ? .red : .orange)
                            }
                        }

                        HStack {
                            Button {
                                UIPasteboard.general.string = candidate.selector
                            } label: {
                                Label("Copy Selector", systemImage: "doc.on.doc")
                            }

                            Button {
                                UIPasteboard.general.string = self.candidateSnippet(candidate)
                            } label: {
                                Label("Copy Snippet", systemImage: "curlybraces")
                            }

                            if self.canApplyCandidate(candidate) {
                                Button {
                                    self.applyCandidate(candidate)
                                } label: {
                                    Label("Apply to Draft", systemImage: "square.and.pencil")
                                }
                            } else {
                                Label("Snippet Only", systemImage: "doc.text")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .font(.caption)
                    }
                }
            } else {
                self.secondaryText("No candidate recommendations.")
            }
        }
    }

    private func diagnosisSection(session: RuleDebugSession) -> some View {
        Section("Diagnosis") {
            LabeledContent("Status") {
                Text(session.status.rawValue)
                    .foregroundColor(self.statusColor(session.status))
            }
            LabeledContent("Source", value: session.input.sourceName)
            LabeledContent("Stage", value: session.input.stage.rawValue)
            LabeledContent("Rule", value: session.input.ruleID ?? "Default")

            if let keyword: String = session.input.keyword {
                LabeledContent("Keyword", value: keyword)
            }

            if let tabID: String = session.input.tabID {
                LabeledContent("Tab", value: tabID)
            }

            if let page: Int = session.input.page {
                LabeledContent("Page", value: "\(page)")
            }

            if let urlOverride: String = session.input.url {
                LabeledContent("URL Override", value: urlOverride)
            }

            if session.issues.isEmpty {
                self.secondaryText("No issues.")
            } else {
                ForEach(session.issues) { issue in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(issue.severity.rawValue) · \(issue.category.rawValue)")
                            .font(.headline)
                            .foregroundColor(self.issueColor(issue.severity))

                        if let field: RuleDebugField = issue.field {
                            self.keyValueLine("Field", field.rawValue)
                        }

                        Text(issue.message)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func requestSection(_ logs: [RuleDebugRequestLog]) -> some View {
        Section("Request") {
            if logs.isEmpty {
                self.secondaryText("No request was sent.")
            } else {
                ForEach(logs) { log in
                    VStack(alignment: .leading, spacing: 6) {
                        self.keyValueLine("URL", log.url)
                        self.keyValueLine("Method", log.method)
                        self.keyValueLine("Headers", "\(log.requestSummary.headerCount)")
                        self.keyValueLine("WebView", log.requestSummary.needsWebView ? "Yes" : "No")
                        self.keyValueLine("Auto Scroll", log.requestSummary.autoScroll ? "Yes" : "No")

                        if let contentLength: Int = log.responseSummary?.contentLength {
                            self.keyValueLine("Content Length", "\(contentLength)")
                        }

                        if let errorMessage: String = log.errorMessage {
                            self.keyValueLine("Error", errorMessage)
                        }
                    }
                }
            }
        }
    }

    private func extractionSection(_ logs: [RuleDebugExtractionLog]) -> some View {
        Section("Extraction") {
            if logs.isEmpty {
                self.secondaryText("No extraction logs.")
            } else {
                ForEach(logs) { log in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(log.field?.rawValue ?? "unknown")
                            .font(.headline)
                        self.secondaryText(log.selector ?? "No selector")
                        self.keyValueLine("Candidates", log.candidateCount.map { count in "\(count)" } ?? "Unknown")
                        self.keyValueLine("Output", log.outputCount.map { count in "\(count)" } ?? "Unknown")

                        if log.samples.isEmpty == false {
                            self.keyValueLine("Samples", log.samples.joined(separator: " · "))
                        }

                        if let message: String = log.message {
                            self.secondaryText(message)
                        }
                    }
                }
            }
        }
    }

    private func paginationSection(_ pagination: PaginationResolution?) -> some View {
        Section("Pagination") {
            if let pagination: PaginationResolution = pagination {
                self.keyValueLine("Current Page", "\(pagination.currentPage)")
                self.keyValueLine("Next Page", pagination.nextPage.map { page in "\(page)" } ?? "None")
                self.keyValueLine("Next URL", pagination.nextURL ?? "None")
                self.keyValueLine("Source", pagination.source?.rawValue ?? "None")
            } else {
                self.secondaryText("No pagination result.")
            }
        }
    }

    private func previewSection(session: RuleDebugSession) -> some View {
        Section("Preview") {
            let items: [RuleDebugPreviewItem] = session.previewItems
            if items.isEmpty {
                self.secondaryText("No preview items.")
            } else {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title)
                            .font(.headline)

                        if let detailURL: String = item.detailURL {
                            self.keyValueLine("Detail", detailURL)
                        }

                        if let chapterURL: String = item.chapterURL {
                            self.keyValueLine("Chapter", chapterURL)
                        }

                        if let imageURL: String = item.imageURL {
                            self.keyValueLine("Image", imageURL)
                        }

                        if let coverURL: String = item.coverURL {
                            self.keyValueLine("Cover", coverURL)
                        }

                        if let latestText: String = item.latestText {
                            self.keyValueLine("Latest", latestText)
                        }

                        if self.canDebugDetail(item: item, session: session) {
                            Button {
                                self.debugDetail(item, session.input.context)
                            } label: {
                                Label("Debug Detail", systemImage: "doc.text.magnifyingglass")
                            }
                            .font(.caption)
                        }

                        if self.canDebugReader(item: item, session: session) {
                            Button {
                                self.debugReader(item, session.input.context)
                            } label: {
                                Label("Debug Reader", systemImage: "photo.on.rectangle.angled")
                            }
                            .font(.caption)
                        }
                    }
                }
            }
        }
    }

    private func canDebugDetail(item: RuleDebugPreviewItem, session: RuleDebugSession) -> Bool {
        guard item.detailURL != nil else {
            return false
        }

        switch session.input.stage {
        case .list, .search:
            return true
        case .detail, .reader:
            return false
        }
    }

    private func canDebugReader(item: RuleDebugPreviewItem, session: RuleDebugSession) -> Bool {
        guard item.chapterURL != nil else {
            return false
        }

        return session.input.stage == .detail
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

    private func statusColor(_ status: RuleDebugSessionStatus) -> Color {
        switch status {
        case .running:
            return .secondary
        case .succeeded:
            return .green
        case .empty:
            return .orange
        case .failed:
            return .red
        }
    }

    private func issueColor(_ severity: RuleDebugIssueSeverity) -> Color {
        switch severity {
        case .info:
            return .secondary
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    private func confidenceColor(_ confidence: RuleCandidateConfidence) -> Color {
        switch confidence {
        case .high:
            return .green
        case .medium:
            return .orange
        case .low:
            return .secondary
        case .rejected:
            return .red
        }
    }

    private func candidateSnippet(_ candidate: RuleCandidate) -> String {
        let escapedSelector: String = self.escape(candidate.selector)
        let escapedParam: String? = candidate.param.map { param in
            return self.escape(param)
        }
        var lines: [String] = [
            "{",
            "  \"selector\": \"\(escapedSelector)\",",
            "  \"selectorKind\": \"\(candidate.selectorKind.rawValue)\",",
            "  \"function\": \"\(candidate.function.rawValue)\""
        ]

        if let escapedParam: String = escapedParam {
            lines[lines.count - 1] += ","
            lines.append("  \"param\": \"\(escapedParam)\"")
        }

        lines.append("}")
        return lines.joined(separator: "\n")
    }

    private func escape(_ value: String) -> String {
        return value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
