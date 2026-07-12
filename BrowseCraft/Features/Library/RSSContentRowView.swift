import SwiftUI

// 中文注释：RSSContentRowView 展示单条 RSS 新闻条目。

struct RSSContentRowView: View {
    let item: ContentItem
    let sourceName: String
    let isFavorite: Bool
    let favoriteAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            self.thumbnail

            VStack(alignment: .leading, spacing: 0) {
                Text(self.categoryText)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(Self.secondaryTextColor)
                    .lineLimit(1)
                    .padding(.top, 6)

                Text(self.item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Self.primaryTextColor)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)

                Spacer(minLength: 0)

                self.dateMetadata
                    .padding(.bottom, 12)
            }
            .frame(height: 100)
        }
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)

            if self.item.coverURL != nil {
                ItemThumbnailImageView(urlString: self.item.coverURL)
                    .frame(width: 90, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.82))
                    .frame(width: 90, height: 90)
                    .overlay(
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundColor(Self.secondaryTextColor)
                    )
            }
        }
        .frame(width: 100, height: 100)
    }

    private var dateMetadata: some View {
        HStack(spacing: 10) {
            if let updatedAt: Date = self.item.updatedAt {
                Label(
                    title: {
                        Text(RSSContentDateFormatter.dayMonthString(from: updatedAt))
                    },
                    icon: {
                        Image(systemName: "calendar")
                    }
                )

                Spacer(minLength: 8)

                Label(
                    title: {
                        Text(RSSContentDateFormatter.timeString(from: updatedAt).lowercased())
                    },
                    icon: {
                        Image(systemName: "clock")
                    }
                )
            } else {
                Label(
                    title: {
                        Text("RSS")
                    },
                    icon: {
                        Image(systemName: "dot.radiowaves.left.and.right")
                    }
                )
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(Self.secondaryTextColor)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private var categoryText: String {
        return "RSS: \(self.sourceName)"
    }

    private static let primaryTextColor: Color = Color(
        red: 25 / 255,
        green: 32 / 255,
        blue: 45 / 255
    )

    private static let secondaryTextColor: Color = Color(
        red: 147 / 255,
        green: 151 / 255,
        blue: 160 / 255
    )
}
