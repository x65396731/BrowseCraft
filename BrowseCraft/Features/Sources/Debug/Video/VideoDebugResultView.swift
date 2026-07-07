import SwiftUI

// 中文注释：VideoDebugResultView 目前只展示视频 URL 手动调试日志，不选择 adapter。
struct VideoDebugResultView: View {
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
