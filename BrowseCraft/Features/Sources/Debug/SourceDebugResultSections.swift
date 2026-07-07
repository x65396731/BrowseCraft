import Foundation
import SwiftUI

struct RuntimeSourcePreviewDebugSection: View {
    let preview: RuntimeSourcePreviewResult

    var body: some View {
        Section("Debug Result") {
            LabeledContent("URL", value: self.preview.entryURL.absoluteString)
            if let title: String = self.preview.title {
                LabeledContent("Title", value: title)
            }
            Text(self.preview.summary)
                .foregroundStyle(.secondary)
        }

        Section("Logs") {
            ForEach(self.preview.logLines, id: \.self) { line in
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

struct RuleDebugSessionSummarySection: View {
    let session: RuleDebugSession

    var body: some View {
        Section("Debug Result") {
            LabeledContent("Status", value: self.session.status.rawValue)
            LabeledContent("Stage", value: self.session.input.stage.rawValue)
            LabeledContent("Rule", value: self.session.input.ruleID ?? "none")
            LabeledContent("Items", value: "\(self.session.previewItems.count)")
            LabeledContent("Issues", value: "\(self.session.issues.count)")
        }

        if self.session.requestLogs.isEmpty == false {
            Section("Request") {
                ForEach(Array(self.session.requestLogs.indices), id: \.self) { index in
                    self.requestLogRow(self.session.requestLogs[index])
                }
            }
        }

        if self.session.extractionLogs.isEmpty == false {
            Section("Extraction") {
                ForEach(Array(self.visibleExtractionLogs.indices), id: \.self) { index in
                    self.extractionLogRow(self.visibleExtractionLogs[index])
                }
            }
        }

        if self.session.previewItems.isEmpty == false {
            Section("Preview Items") {
                ForEach(Array(self.visiblePreviewItems.indices), id: \.self) { index in
                    self.previewItemRow(self.visiblePreviewItems[index])
                }
            }
        }

        if self.session.issues.isEmpty == false {
            Section("Issues") {
                ForEach(Array(self.session.issues.indices), id: \.self) { index in
                    self.issueRow(self.session.issues[index])
                }
            }
        }
    }

    private var visibleExtractionLogs: [RuleDebugExtractionLog] {
        return Array(self.session.extractionLogs.prefix(8))
    }

    private var visiblePreviewItems: [RuleDebugPreviewItem] {
        return Array(self.session.previewItems.prefix(8))
    }

    private func requestLogRow(_ log: RuleDebugRequestLog) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(log.url)
                .font(.footnote)
                .textSelection(.enabled)
            Text(self.requestSummary(log))
                .font(.caption)
                .foregroundStyle(log.errorMessage == nil ? Color.secondary : Color.red)
        }
    }

    private func extractionLogRow(_ log: RuleDebugExtractionLog) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(log.field?.rawValue ?? "unknown")
                .font(.footnote)
            Text(self.extractionSummary(log))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func previewItemRow(_ item: RuleDebugPreviewItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.footnote)
            if let detailURL: String = item.detailURL {
                Text(detailURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func issueRow(_ issue: RuleDebugIssue) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(issue.severity.rawValue)
                .font(.footnote)
                .foregroundStyle(self.issueColor(issue.severity))
            Text(issue.message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func requestSummary(_ log: RuleDebugRequestLog) -> String {
        if let errorMessage: String = log.errorMessage {
            return errorMessage
        }

        let bytes: String = log.responseSummary?.contentLength.map { "\($0) bytes" } ?? "bytes unknown"
        return "\(log.method) · \(bytes)"
    }

    private func extractionSummary(_ log: RuleDebugExtractionLog) -> String {
        let candidateCount: String = log.candidateCount.map { "\($0)" } ?? "unknown"
        let outputCount: String = log.outputCount.map { "\($0)" } ?? "unknown"
        return "candidates \(candidateCount), output \(outputCount)"
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
}
