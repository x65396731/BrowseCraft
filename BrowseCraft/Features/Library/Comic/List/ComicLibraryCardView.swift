import SwiftUI

// 中文注释：ComicLibraryCardView.swift 属于 Library 漫画展示层，用于展示漫画封面和章节入口。

/// 中文注释：ComicLibraryCardView 是漫画源在 Library 中使用的封面卡片。
struct ComicLibraryCardView: View {
    let item: ContentItem
    let primaryActionTitle: String
    let isFavorite: Bool
    let favoriteAction: () -> Void
    let readAction: () -> Void
    let imageRequestConfig: RequestConfig?

    private let titleColor: Color = Color(red: 21 / 255, green: 30 / 255, blue: 71 / 255)
    private let chapterColor: Color = Color(red: 133 / 255, green: 153 / 255, blue: 255 / 255)

    var body: some View {
        self.cardContent
    }

    private var cardContent: some View {
        ZStack(alignment: .topTrailing) {
            Button(
                action: {
                    self.openReaderDestination()
                },
                label: {
                    self.itemContent
                }
            )
            .buttonStyle(.plain)

            self.favoriteButton
                .padding(6)
        }
    }

    private var itemContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            ItemThumbnailImageView(
                urlString: self.item.coverURL,
                refererURLString: self.item.detailURL,
                requestConfig: self.imageRequestConfig
            )
            .aspectRatio(129.0 / 194.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(self.item.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(self.titleColor)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30, alignment: .topLeading)

                if let latestText: String = self.item.latestText {
                    Text(latestText)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(self.chapterColor)
                        .lineLimit(1)
                }
            }
        }
    }

    private var favoriteButton: some View {
        Button(
            action: {
                self.favoriteAction()
            },
            label: {
                Image(systemName: self.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(self.isFavorite ? .yellow : .white)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.45))
                    )
            }
        )
        .buttonStyle(.plain)
        .accessibilityLabel(self.isFavorite ? "Remove Favorite" : "Add Favorite")
    }

    private func openReaderDestination() {
        #if DEBUG
        print(
            "[BrowseCraftNavigation] Tap \(self.primaryActionTitle) " +
            "itemId=\(self.item.id) " +
            "title=\(self.item.title) " +
            "detailURL=\(self.item.detailURL) " +
            "latestText=\(self.item.latestText ?? "nil")"
        )
        #endif

        self.readAction()
    }
}
