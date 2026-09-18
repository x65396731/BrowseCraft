import SwiftUI
import UIKit

struct AppBootstrapFailureView: View {
    let failure: AppBootstrapFailure
    @State private var hasCopiedDiagnostics: Bool = false

    var body: some View {
        ContentUnavailableView {
            Label(self.failure.title, systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            VStack(spacing: 12) {
                Text(self.failure.message)
                Text(self.failure.recoverySuggestion)
                Text(self.failure.diagnosticCode)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        } actions: {
            // 中文注释：诊断码只够定位「哪一类错误」，摘要里才有状态码。整段复制，省掉用户转述。
            Button {
                UIPasteboard.general.string = self.failure.copyableDiagnostics
                self.hasCopiedDiagnostics = true
            } label: {
                Label(
                    self.hasCopiedDiagnostics
                        ? NSLocalizedString("Copied", comment: "引导失败页：诊断信息已复制")
                        : NSLocalizedString("Copy Diagnostics", comment: "引导失败页：复制诊断信息"),
                    systemImage: self.hasCopiedDiagnostics ? "checkmark" : "doc.on.doc"
                )
            }
        }
        .padding()
    }
}
