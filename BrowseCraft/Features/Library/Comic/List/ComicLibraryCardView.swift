import BrowseCraftCore
import BrowseCraftDomain
import SwiftUI

// 中文注释：ComicLibraryCardView 是库页漫画库的封面卡片（`docs/design/Library-Comic-Page-Redesign-Design.md` 第五节）：
// 三列封面墙里的一张。封面上只压本机的「读到哪」与「已收藏」两个小标记，规则给的最新话放在封面下第二行；
// 没读过、没收藏的封面是干净的。搜索结果复用同一张卡片。

/// 封面 2:3 圆角 10 + 标题两行 + 最新话一行。点 = 进漫画详情；长按「打开」「继续读 · 4-2」（读过时）「收藏 / 取消收藏」。
struct ComicLibraryCardView: View {
    let item: ContentItem
    let isFavorite: Bool
    /// 封面左下角标「读到 4-2」；这部没读过为 nil。
    let progressBadgeText: String?
    /// 长按菜单「继续读 · 4-2」里的编号；nil 时不出这一项（没读过，或当前页面不接阅读器入口，如搜索页）。
    let continueChapterLabel: String?
    let imageRequestConfig: RequestConfig?
    let openAction: () -> Void
    let favoriteAction: () -> Void
    let continueReadingAction: () -> Void

    private static let coverCornerRadius: CGFloat = 10
    /// 漫画类型样式：类型色给最新话，固定深色取值给角标与爱心——压在任何封面上都读得清。
    private var style: CatalogKindStyle {
        return CatalogKindStyle.of(CatalogSourceKind.comic)
    }

    var body: some View {
        Button(
            action: {
                self.openDetail()
            },
            label: {
                self.itemContent
            }
        )
        .buttonStyle(ComicLibraryCardButtonStyle())
        .contextMenu {
            Button {
                self.openDetail()
            } label: {
                Label(NSLocalizedString("library_card_open", comment: ""), systemImage: "list.bullet.rectangle")
            }
            if let continueChapterLabel: String = self.continueChapterLabel {
                Button {
                    self.continueReadingAction()
                } label: {
                    Label(
                        String(format: NSLocalizedString("library_card_continue_reading", comment: ""), continueChapterLabel),
                        systemImage: "book"
                    )
                }
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
    }

    private var itemContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            ItemThumbnailImageView(
                urlString: self.item.coverURL,
                refererURLString: self.item.detailURL,
                requestConfig: self.imageRequestConfig,
                placeholderImageName: "ComicListPlaceholder"
            )
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Self.coverCornerRadius, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if let progressBadgeText: String = self.progressBadgeText {
                    Text(progressBadgeText)
                        .font(.caption2.weight(.bold))
                        .lineLimit(1)
                        .foregroundStyle(CatalogKindStyle.bannerIconInk)
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(self.style.bannerAccent, in: Capsule())
                        .padding(6)
                }
            }
            .overlay(alignment: .topTrailing) {
                // 中文注释：只在已收藏时压一颗小爱心；收藏 / 取消走长按菜单，封面上不放按钮（第十一节裁定）。
                if self.isFavorite {
                    Image("TabFavorites")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .foregroundColor(self.style.bannerAccent)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(CatalogPalette.coverScrim))
                        .padding(6)
                        .accessibilityLabel(NSLocalizedString("library_card_favorited", comment: ""))
                }
            }
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: Self.coverCornerRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                // 中文注释：两行定高，同一行的卡片底边对齐。
                Text(self.item.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34, alignment: .topLeading)

                // 中文注释：最新话照原文一行；没有也留出行位，让同一行的卡片对齐。
                Text(self.latestText ?? " ")
                    .font(.caption2)
                    .foregroundStyle(self.style.accent)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityHidden(self.latestText == nil)
            }
        }
    }

    private var latestText: String? {
        guard let text: String = self.item.latestText?.trimmingCharacters(in: .whitespacesAndNewlines),
              text.isEmpty == false else {
            return nil
        }
        return text
    }

    private func openDetail() {
        #if DEBUG
        AppDebugLog.write(
            "[BrowseCraftNavigation] Tap comic card " +
            "itemId=\(self.item.id) " +
            "title=\(self.item.title) " +
            "detailURL=\(self.item.detailURL) " +
            "latestText=\(self.item.latestText ?? "nil")"
        )
        #endif

        self.openAction()
    }
}

/// 按下整卡变淡。
private struct ComicLibraryCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}
