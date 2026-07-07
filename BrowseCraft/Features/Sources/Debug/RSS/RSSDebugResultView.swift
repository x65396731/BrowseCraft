import SwiftUI

// 中文注释：RSSDebugResultView 展示 RSS/Atom 固定 parser 的请求、解析和原文预览。
struct RSSDebugResultView: View {
    let result: RuntimeRSSDebugResult

    var body: some View {
        Section("Request") {
            LabeledContent("URL", value: self.result.entryURL.absoluteString)
            LabeledContent("Bytes", value: "\(self.result.byteCount)")
        }

        Section("Parser") {
            if let parserError: String = self.result.parserError {
                LabeledContent("Status", value: "failed")
                Text(parserError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            } else {
                LabeledContent("Status", value: "success")
            }

            if let feedTitle: String = self.result.feedTitle {
                LabeledContent("Feed title", value: feedTitle)
            }
            if let itemCount: Int = self.result.itemCount {
                LabeledContent("Items", value: "\(itemCount)")
            }
            if let firstItemTitle: String = self.result.firstItemTitle {
                LabeledContent("First item", value: firstItemTitle)
            }
        }

        Section("Logs") {
            ForEach(self.result.logLines, id: \.self) { line in
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }

        Section("Raw Preview") {
            Text(self.result.rawPreview.isEmpty ? "No body returned." : self.result.rawPreview)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}
