import SwiftUI
import UIKit

// 中文注释：RuleDebugResultView 是 HTML/规则类调试结果视图，供已保存规则和添加源调试共同复用。
struct RuleDebugResultView: View {
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
