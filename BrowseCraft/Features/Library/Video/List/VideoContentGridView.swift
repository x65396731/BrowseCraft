import BrowseCraftCore
import BrowseCraftDomain
import SwiftUI

// 中文注释：VideoContentGridView 是 Library 的视频源列表——两列海报墙（`docs/design/Library-Video-Page-Redesign-Design.md` 第四节），
// 不复用漫画卡片入口。集数与收藏态都压在封面上，标题下不再有第二行。
struct VideoContentGridView: View {
    let items: [ContentItem]
    let source: Source
    let favoriteItemIDs: Set<String>
    let favoriteAction: (ContentItem) -> Void
    let nextPage: Int?
    let loadNextPage: () -> Void
    let contentViewModelFactory: LibraryContentViewModelFactory
    let imageRequestConfig: RequestConfig?
    /// 中文注释：分页脚的文字；nil 时不画分页脚（规则不支持分页、搜索结果）。
    var paginationStatusText: String? = nil
    var isLoadingNextPage: Bool = false
    @State private var selectedItem: ContentItem?

    /// 中文注释：两列、列距 14；iPad 与横屏按最小宽 160 自适应成更多列。
    private let gridColumns: [GridItem] = [
        GridItem(.adaptive(minimum: 160), spacing: 14)
    ]

    var body: some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: self.gridColumns, spacing: 20) {
                ForEach(self.items, id: \.id) { item in
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

                if let nextPage: Int = self.nextPage {
                    Color.clear
                        .frame(height: 1)
                        .id("video-pagination-\(self.source.id)-\(nextPage)")
                        .onAppear {
                            self.loadNextPage()
                        }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            if let paginationStatusText: String = self.paginationStatusText {
                LibraryPaginationFooterView(
                    statusText: paginationStatusText,
                    isLoading: self.isLoadingNextPage
                )
            }
        }
        .navigationDestination(item: self.$selectedItem) { item in
            VideoDetailView(
                item: item,
                source: self.source,
                factory: self.contentViewModelFactory
            )
        }
        .onAppear {
            #if DEBUG
            AppDebugLog.write(
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

/// 海报卡片：封面 2:3 圆角 14，集数徽章压左下、爱心压右上，标题两行定高。点 = 进影视详情；长按「打开」「收藏 / 取消收藏」。
private struct VideoLibraryCardView: View {
    let item: ContentItem
    let primaryActionTitle: String
    let isFavorite: Bool
    let favoriteAction: () -> Void
    let openAction: () -> Void
    let imageRequestConfig: RequestConfig?

    private static let coverCornerRadius: CGFloat = 14
    /// 视频类型样式：徽章与已收藏爱心取它的固定强调色。
    private var style: CatalogKindStyle {
        return CatalogKindStyle.of(CatalogSourceKind.video)
    }

    var body: some View {
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
            .contextMenu {
                Button {
                    self.openDetailDestination()
                } label: {
                    Label(NSLocalizedString("library_card_open", comment: ""), systemImage: "play.rectangle")
                }
                Button {
                    self.favoriteAction()
                } label: {
                    Label(
                        NSLocalizedString(self.isFavorite ? "favorites_unfavorite" : "library_card_favorite", comment: ""),
                        systemImage: self.isFavorite ? "heart.slash" : "heart"
                    )
                }
            }

            self.favoriteButton
                .padding(8)
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
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Self.coverCornerRadius, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                // 中文注释：集数徽章取类型横幅图标圆的固定深色取值——压在任何封面上都读得清；没有 latestText 就不出。
                if let latestText: String = self.item.latestText?.trimmingCharacters(in: .whitespacesAndNewlines),
                   latestText.isEmpty == false {
                    Text(latestText)
                        .font(.caption2.weight(.bold))
                        .lineLimit(1)
                        .foregroundStyle(CatalogKindStyle.bannerIconInk)
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(self.style.bannerAccent, in: Capsule())
                        .padding(8)
                }
            }
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: Self.coverCornerRadius, style: .continuous))

            Text(self.item.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40, alignment: .topLeading)
        }
    }

    private var favoriteButton: some View {
        Button(
            action: {
                self.favoriteAction()
            },
            label: {
                // 中文注释：与底栏「收藏」同一个心形——实心取 TabFavorites，空心是从同一剪影内缩出的
                // TabFavoritesOutline，两者都是模板图，颜色由 foregroundColor 决定。
                // 已收藏用视频强调色（与集数徽章同色），不再用粉色。
                Image(self.isFavorite ? "TabFavorites" : "TabFavoritesOutline")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundColor(self.isFavorite ? self.style.bannerAccent : .white)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.4))
                    )
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
        )
        .buttonStyle(.plain)
        .accessibilityLabel(
            NSLocalizedString(self.isFavorite ? "favorites_unfavorite" : "library_card_favorite", comment: "")
        )
    }

    private func openDetailDestination() {
        #if DEBUG
        AppDebugLog.write(
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
