import SwiftUI

// 中文注释：SourceDebugInputSection 是三端 Debug 共用的 URL 输入区。
struct SourceDebugInputSection: View {
    @Binding var entryURL: String
    let isRunning: Bool

    var body: some View {
        Section("Input") {
            TextField("URL", text: self.$entryURL)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .disabled(self.isRunning)
        }
    }
}
