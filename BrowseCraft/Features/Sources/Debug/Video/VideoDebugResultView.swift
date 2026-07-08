import SwiftUI
import BrowseCraftCore

// 中文注释：VideoDebugResultView 展示手动 video 配置跑 runtime 后的列表调试结果。
struct VideoDebugResultView: View {
    let result: ManualVideoSourceDebugResult

    var body: some View {
        Section("Debug Result") {
            LabeledContent("Status", value: self.result.listOutput.diagnostics.status.rawValue)
            LabeledContent("Items", value: "\(self.result.listOutput.items.count)")
            LabeledContent("Source", value: self.result.source.name)
            LabeledContent("Entry", value: self.result.inspection.entryKind.rawValue)
        }

        if self.result.listOutput.items.isEmpty == false {
            Section("Preview Items") {
                ForEach(self.result.listOutput.items.prefix(5), id: \.id) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.footnote)
                        if let detailURL = item.detailURL {
                            Text(detailURL.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        if let coverURL = item.coverURL {
                            Text(coverURL.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }

        if self.result.listOutput.diagnostics.requestLogs.isEmpty == false {
            Section("Request") {
                ForEach(self.result.listOutput.diagnostics.requestLogs, id: \.url) { log in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(log.url.absoluteString)
                            .font(.footnote)
                            .textSelection(.enabled)
                        Text(self.requestSummary(log))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        if self.result.listOutput.diagnostics.issues.isEmpty == false {
            Section("Issues") {
                ForEach(self.result.listOutput.diagnostics.issues) { issue in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(issue.severity.rawValue)
                            .font(.footnote)
                        Text(issue.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func requestSummary(_ log: SourceRequestLog) -> String {
        let bytes: String = log.contentLength.map { "\($0) bytes" } ?? "bytes unknown"
        return "\(log.method) · headers \(log.headerCount) · \(bytes)"
    }
}
