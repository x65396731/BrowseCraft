import SwiftUI

struct SettingsRow: View {
    /// 资产目录里的模板图名（Settings*.imageset，22pt 纯黑剪影），着色由 accentColor 决定。
    let image: String
    let title: String
    let detail: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(self.image)
                .foregroundColor(.accentColor)
                .frame(width: 24)

            Text(self.title)

            Spacer()

            if let detail: String = self.detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}
