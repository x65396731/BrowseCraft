import BrowseCraftCore
import BrowseCraftDomain
import SwiftUI

// 中文注释：BookLibraryRowView 是库页书籍库的书脊行（`docs/design/Library-Book-Page-Redesign-Design.md` 第五节）：
// 单列、一行一本。书靠书名和章节文字识别，封面退成 60pt 的辅助；文字有三行的位置——书名两行、最新章、读到哪——
// 互不相挤。文字书与有声书同一行，整站有声时封面右下压耳机、措辞换「听」。搜索结果复用同一行。

/// 左封面 60×80 + 右侧三行文字 + 行尾已收藏爱心。点 = 进站点书详情；长按「打开」「继续读 / 继续听 · 章节名」（读过时）「收藏 / 取消收藏」。
struct BookLibraryRowView: View {
    let item: ContentItem
    let isFavorite: Bool
    /// 整站有声：封面右下压耳机（`docs/design/Library-Book-Page-Redesign-Design.md` 第二节）。
    let isAudiobook: Bool
    /// 第三行「读到 · 章节名」；没读过为 nil。
    let readToText: String?
    /// 长按菜单「继续读 · 章节名」的整句；nil 时不出这一项（没读过，或当前页面不接阅读器入口，如搜索页）。
    let continueMenuTitle: String?
    let imageRequestConfig: RequestConfig?
    let openAction: () -> Void
    let favoriteAction: () -> Void
    let continueReadingAction: () -> Void

    private static let coverCornerRadius: CGFloat = 8
    /// 书籍类型样式：类型色给最新章、读到哪的圆点与已收藏爱心。
    private var style: CatalogKindStyle {
        return CatalogKindStyle.of(CatalogSourceKind.book)
    }

    var body: some View {
        Button(action: self.openAction) {
            self.rowContent
        }
        .buttonStyle(BookLibraryRowButtonStyle())
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contextMenu {
            Button(action: self.openAction) {
                Label(NSLocalizedString("library_card_open", comment: ""), systemImage: "list.bullet.rectangle")
            }
            if let continueMenuTitle: String = self.continueMenuTitle {
                Button(action: self.continueReadingAction) {
                    Label(continueMenuTitle, systemImage: self.isAudiobook ? "headphones" : "book")
                }
            }
            Button(action: self.favoriteAction) {
                Label(
                    NSLocalizedString(self.isFavorite ? "favorites_unfavorite" : "library_card_favorite", comment: ""),
                    systemImage: self.isFavorite ? "heart.slash" : "heart"
                )
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            self.cover

            VStack(alignment: .leading, spacing: 4) {
                Text(self.item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                if let latestText: String = self.latestText {
                    Text(String(format: NSLocalizedString("library_book_latest", comment: ""), latestText))
                        .font(.footnote)
                        .foregroundStyle(self.style.accent)
                        .lineLimit(1)
                }

                if let readToText: String = self.readToText {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(self.style.accent)
                            .frame(width: 6, height: 6)
                        Text(readToText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 中文注释：只在已收藏时显示；收藏 / 取消走长按菜单，行上不放按钮（第十一节裁定）。
            if self.isFavorite {
                Image("TabFavorites")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .foregroundColor(self.style.accent)
                    .accessibilityLabel(NSLocalizedString("library_card_favorited", comment: ""))
            }
        }
        .padding(.vertical, 10)
    }

    /// 封面 60×80 圆角 8，左缘 2pt 书脊线让它像本书而不是卡片；整站有声时右下压耳机。
    private var cover: some View {
        ItemThumbnailImageView(
            urlString: self.item.coverURL,
            refererURLString: self.item.detailURL,
            requestConfig: self.imageRequestConfig,
            placeholderImageName: "BookCoverPlaceholder"
        )
        .frame(width: 60, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: Self.coverCornerRadius, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.black.opacity(0.18))
                .frame(width: 2)
                .clipShape(RoundedRectangle(cornerRadius: Self.coverCornerRadius, style: .continuous))
        }
        .overlay(alignment: .bottomTrailing) {
            if self.isAudiobook {
                Image(systemName: "headphones")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.black.opacity(0.4)))
                    .padding(4)
                    .accessibilityHidden(true)
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
}

/// 按下整行底色变 `fillBackground`。
private struct BookLibraryRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(configuration.isPressed ? CatalogPalette.fillBackground : Color.clear)
                    .padding(.horizontal, -8)
            )
    }
}
