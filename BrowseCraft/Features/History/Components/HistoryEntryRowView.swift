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
        case .comic:
            return "book.pages"
        case .video:
            return "play.rectangle"
        case .book:
            return "book"
        case .temporary:
            if self.entry.temporaryHistory?.kind == .comic {
                return "book.pages"
            }

            return "play.rectangle"
        }
    }

    /// 中文注释：第三行显示来自哪个来源，不显示章节 / 播放页的完整网址——网址对用户没有信息量，
    /// 长网址还会把一行撑成三行。临时资源没有来源，退一步只显示域名。
    private var detailText: String? {
        switch self.entry.kind {
        case .comic:
            return self.entry.comicHistory?.sourceSnapshot?.name
        case .video:
            return self.entry.videoHistory.flatMap { $0.sourceName ?? $0.sourceSnapshot?.name }
        case .book:
            return self.entry.bookHistory?.sourceSnapshot?.name
        case .temporary:
            return self.entry.temporaryHistory?.resourceURL.host
        }
    }
}
