import SwiftUI

struct SettingsRow: View {
    let systemImage: String
    let title: String
    let detail: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: self.systemImage)
                .font(.body)
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
