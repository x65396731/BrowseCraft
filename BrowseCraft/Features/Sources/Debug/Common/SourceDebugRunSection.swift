import SwiftUI

// 中文注释：SourceDebugRunSection 是三端 Debug 共用的运行控制区。
struct SourceDebugRunSection: View {
    let kind: RuntimeSourceImportKind
    let isRunning: Bool
    let canRun: Bool
    let runAction: () -> Void

    var body: some View {
        Section("Runtime") {
            LabeledContent("Type", value: self.kind.displayTitle)
            Text(self.kind.debugSummary)
                .foregroundStyle(.secondary)

            Button(self.isRunning ? "Running..." : "Run Debug", action: self.runAction)
                .disabled(self.canRun == false)
        }
    }
}
