import SwiftUI

// 中文注释：VideoContentGridView 是 Library 的视频源列表，不复用漫画卡片入口。
struct VideoContentGridView: View {
    let items: [ContentItem]
    let source: Source
    let favoriteItemIDs: Set<String>
    let favoriteAction: (ContentItem) -> Void
    let contentViewModelFactory: LibraryContentViewModelFactory
    let imageRequestConfig: RequestConfig?
    @State private var selectedItem: ContentItem?

    private let gridColumns: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: self.gridColumns, spacing: 16) {
                ForEach(Array(self.items.enumerated()), id: \.offset) { _, item in
                    VideoLibraryCardView(
                        item: item,
                        primaryActionTitle: "Episodes",
                        isFavorite: self.favoriteItemIDs.contains(item.id),
                        favoriteAction: {
                            self.favoriteAction(item)
                        },
                        openAction: {
                            self.selectedItem = item
                        },
                        imageRequestConfig: self.imageRequestConfig
                    )
                }
            }
        }
        .padding(16)
        .navigationDestination(item: self.$selectedItem) { item in
            VideoDetailView(
                item: item,
                source: self.source,
                factory: self.contentViewModelFactory
            )
        }
        .onAppear {
            #if DEBUG
            print(
                "[BrowseCraftVideoUI] grid appear " +
                "source=\(self.source.id) " +
                "kind=\(self.source.configuration.kind.rawValue) " +
                "items=\(self.items.count) " +
                "firstItem=\(self.items.first?.id ?? "nil")"
            )
            #endif
        }
    }
}

private struct VideoLibraryCardView: View {
    let item: ContentItem
    let primaryActionTitle: String
    let isFavorite: Bool
    let favoriteAction: () -> Void
    let openAction: () -> Void
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
                    self.openDetailDestination()
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
                requestConfig: self.imageRequestConfig,
                placeholderImageName: "VideoListPlaceholder"
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

    private func openDetailDestination() {
        #if DEBUG
        print(
            "[BrowseCraftNavigation] Tap \(self.primaryActionTitle) " +
            "itemId=\(self.item.id) " +
            "title=\(self.item.title) " +
            "detailURL=\(self.item.detailURL) " +
            "latestText=\(self.item.latestText ?? "nil")"
        )
        #endif

        self.openAction()
    }
}
