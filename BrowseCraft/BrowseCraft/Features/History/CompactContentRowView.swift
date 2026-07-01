import SwiftUI

struct CompactContentRowView: View {
    let item: ContentItem
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            CoverImageView(urlString: self.item.coverURL)
                .frame(width: 48, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(self.item.title)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(2)

                Text(self.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
