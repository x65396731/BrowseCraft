import BrowseCraftCore
import BrowseCraftDomain
import SwiftUI

// 中文注释：收藏页与历史页共用的封面卡片行零件（`docs/design/Favorites-Page-Redesign-Design.md`、
// `docs/design/History-Page-Redesign-Design.md`）：封面 + 类型徽标、卡片组里的一行、列表行留白、撤销提示条。
// 取值都来自 `CatalogStyle.swift`，这里不声明颜色。

/// 作品封面：走库页同一个封面管线，左下角压类型徽标（类型色 + 类型图标，不只靠颜色区分）。
/// 知道播放进度时在封面底边画一条进度条。
struct ContentCoverView: View {
    enum Badge {
        /// 浅 / 深页面上的卡片：类型色底 + 系统底色图形。
        case card
        /// 固定深色的类型色块（历史页继续卡片）：色块强调色底 + 深色图形。
        case tile
    }

    let urlString: String?
    let refererURLString: String?
    let requestConfig: RequestConfig?
    let kind: CatalogSourceKind
    var width: CGFloat = 56
    var height: CGFloat = 78
    var cornerRadius: CGFloat = 10
    var badge: Badge = .card
    /// 0...1；nil 时不画进度条。
    var progress: Double? = nil

    private static let progressHeight: CGFloat = 3

    var body: some View {
        let style: CatalogKindStyle = CatalogKindStyle.of(self.kind)
        ItemThumbnailImageView(
            urlString: self.urlString,
            refererURLString: self.refererURLString,
            requestConfig: self.requestConfig,
            placeholderImageName: Self.placeholderName(for: self.kind)
        )
        .frame(width: self.width, height: self.height)
        .overlay(alignment: .bottom) {
            if let progress: Double = self.progress {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.black.opacity(0.28))
                        Rectangle()
                            .fill(style.accent)
                            .frame(width: proxy.size.width * min(max(progress, 0), 1))
                    }
                }
                .frame(height: Self.progressHeight)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            Image(systemName: style.symbolName)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(self.badge == .tile ? CatalogKindStyle.bannerIconInk : Color(uiColor: .systemBackground))
                .frame(width: 18, height: 18)
                .background(self.badge == .tile ? style.bannerAccent : style.accent, in: Circle())
                .padding(4)
                .padding(.bottom, self.progress == nil ? 0 : Self.progressHeight + 2)
                .accessibilityHidden(true)
        }
        .accessibilityHidden(true)
    }

    static func placeholderName(for kind: CatalogSourceKind) -> String {
        switch kind {
        case .video:
            return "VideoListPlaceholder"
        case .comic:
            return "ComicListPlaceholder"
        case .book:
            return "BookCoverPlaceholder"
        }
    }
}

extension View {
    /// 卡片组里的一行：同一组的行拼成一张圆角 18 的卡片——首行圆上角、末行圆下角，行间细线从 82pt 起。
    func contentCardGroupRow(isFirst: Bool, isLast: Bool) -> some View {
        return self.modifier(ContentCardGroupRowModifier(isFirst: isFirst, isLast: isLast))
    }

    /// 自绘页面里 `List` 的一行：去掉系统行底色与分隔线，左右留白、上下间距由调用处给。
    func contentListPageRow(top: CGFloat = 0, bottom: CGFloat = 0, horizontal: CGFloat = 20) -> some View {
        return self
            .listRowInsets(EdgeInsets(top: top, leading: horizontal, bottom: bottom, trailing: horizontal))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

private struct ContentCardGroupRowModifier: ViewModifier {
    let isFirst: Bool
    let isLast: Bool

    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CatalogPalette.cardBackground)
            .overlay(alignment: .top) {
                if self.isFirst == false {
                    Rectangle()
                        .fill(Color(uiColor: .separator))
                        .frame(height: 1 / self.displayScale)
                        .padding(.leading, 82)
                }
            }
            .clipShape(self.shape)
            .contentShape(.interaction, self.shape)
            .contentShape(.contextMenuPreview, self.shape)
    }

    private var shape: UnevenRoundedRectangle {
        let top: CGFloat = self.isFirst ? 18 : 0
        let bottom: CGFloat = self.isLast ? 18 : 0
        return UnevenRoundedRectangle(
            topLeadingRadius: top,
            bottomLeadingRadius: bottom,
            bottomTrailingRadius: bottom,
            topTrailingRadius: top,
            style: .continuous
        )
    }
}

/// 轻操作之后的底部提示：「已取消收藏「作品名」 · 撤销」这类，几秒后自动消失。反色胶囊，与页面明暗相反。
struct ContentUndoBanner: View {
    let message: String
    let actionTitle: String
    let undoAction: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(self.message)
                .font(.subheadline)
                .foregroundStyle(Color(uiColor: .systemBackground))
                .lineLimit(1)
            Spacer(minLength: 0)
            Button(self.actionTitle, action: self.undoAction)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CatalogPalette.inverseAction)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
        }
        .padding(.leading, 20)
        .padding(.trailing, 10)
        .frame(height: 52)
        .background(Color.primary, in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
        .accessibilityElement(children: .combine)
    }
}
