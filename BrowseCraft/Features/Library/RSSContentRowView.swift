import SwiftUI

// 中文注释：RSSContentRowView 展示单条 RSS 新闻条目。

struct RSSContentRowView: View {
    let item: ContentItem
    let sourceName: String
    let isFavorite: Bool
    let favoriteAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                if self.item.coverURL != nil {
                    CoverImageView(urlString: self.item.coverURL)
                        .frame(width: 96, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(self.item.title)
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Label(
                            title: {
                                Text("RSS")
                            },
                            icon: {
                                Image(systemName: "dot.radiowaves.left.and.right")
                            }
                        )

                        Text(self.sourceName)

                        if let updatedAt: Date = self.item.updatedAt {
                            Text(RSSContentDateFormatter.string(from: updatedAt))
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                }

                Button(
                    action: {
                        self.favoriteAction()
                    },
                    label: {
                        Image(systemName: self.isFavorite ? "star.fill" : "star")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(self.isFavorite ? .yellow : .secondary)
                            .frame(width: 32, height: 32)
                    }
                )
                .buttonStyle(.plain)
                .accessibilityLabel(self.isFavorite ? "Remove Favorite" : "Add Favorite")
            }

            if let summary: String = self.summaryText {
                Text(summary)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                Text("Read")
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
            }
            .font(.callout.weight(.semibold))
            .foregroundColor(.blue)
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(.separator), lineWidth: 1)
        )
    }

    private var summaryText: String? {
        return RSSContentTextFormatter.sanitized(self.item.latestText)
    }
}
