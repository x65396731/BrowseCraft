import SwiftUI
import UIKit

// 中文注释：系统分享面板。设置页「导出诊断日志」用它把合成好的日志文件交给用户选择去处（邮件、AirDrop、存到文件）。

/// 中文注释：分享的条目；`Identifiable` 让 `.sheet(item:)` 每次导出都弹一次新面板。
struct ActivityShareItem: Identifiable {
    let id: UUID = UUID()
    let url: URL
}

struct ActivityShareSheet: UIViewControllerRepresentable {
    let item: ActivityShareItem

    func makeUIViewController(context: Context) -> UIActivityViewController {
        return UIActivityViewController(activityItems: [self.item.url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
