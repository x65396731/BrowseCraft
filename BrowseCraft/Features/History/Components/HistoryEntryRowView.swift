import SwiftUI

struct HistoryEntryRowView: View {
    let entry: ReadingHistoryEntry
    let dateText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: self.iconName)
                    .foregroundColor(.secondary)
                    .frame(width: 18)

                Text(self.entry.title)
                    .font(.body.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
            }

            if let subtitle: String = self.entry.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            if let detail: String = self.detailText {
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }

            Text(self.dateText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        switch self.entry.kind {
        case .rss:
            return "dot.radiowaves.left.and.right"
        case .comic:
            return "book.pages"
        case .video:
            return "play.rectangle"
        case .temporary:
            if self.entry.temporaryHistory?.kind == .comic {
                return "book.pages"
            }

            return "play.rectangle"
        }
    }

    private var detailText: String? {
        switch self.entry.kind {
        case .rss:
            return self.entry.rssHistory?.dataContent
        case .comic:
            return self.entry.comicHistory?.chapterURL?.absoluteString
        case .video:
            return self.entry.videoHistory?.playPageURL.absoluteString
        case .temporary:
            return self.entry.temporaryHistory?.resourceURL.absoluteString
        }
    }
}
