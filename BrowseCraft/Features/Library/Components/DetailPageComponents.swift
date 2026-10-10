import SwiftUI

// 中文注释：漫画详情与书详情共用的页面件（2026-10-11 复审「跨页复制」第三组，用户裁定统一取值）：
// 继续卡片、开始按钮、固定的返回 / 收藏圆按钮、贴顶章节分区头、分区头上方的底色补铺。影视详情是深色头图版式，只共用开始按钮之外的逻辑件。

/// 继续卡片：通栏、高 88、圆角 16、卡片底、左缘 4pt 类型色竖条；左缩略图 56×72（调用方给内容，本件只定尺寸与圆角 8）；
/// 中间「继续阅读」`caption` semibold 类型色 → 章名 `headline` → 小字 `caption` 次级；右 36pt 类型色圆底图标；底边 3pt 进度条。
struct DetailContinueCard<Thumbnail: View>: View {
    let label: String
    let title: String
    let subtitle: String?
    let progress: Double?
    let iconName: String
    let accent: Color
    let action: () -> Void
    @ViewBuilder let thumbnail: () -> Thumbnail

    var body: some View {
        Button(action: self.action) {
            HStack(spacing: 14) {
                self.thumbnail()
                    .frame(width: 56, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(self.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(self.accent)
                    Text(self.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let subtitle: String = self.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: self.iconName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CatalogPalette.onAccent)
                    .frame(width: 36, height: 36)
                    .background(self.accent, in: Circle())
                    .accessibilityHidden(true)
            }
            .padding(.leading, 20)
            .padding(.trailing, 16)
            .frame(height: 88)
            .frame(maxWidth: .infinity)
            .background(CatalogPalette.cardBackground)
            .overlay(alignment: .leading) {
                self.accent.frame(width: 4)
            }
            .overlay(alignment: .bottom) {
                if let progress: Double = self.progress {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            CatalogPalette.fillBackground
                            self.accent.frame(width: proxy.size.width * progress)
                        }
                    }
                    .frame(height: 3)
                    .accessibilityHidden(true)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// 开始按钮：通栏胶囊、高 50、类型色底、`callout` semibold；图标 + 文案。
struct DetailStartButton: View {
    let iconName: String
    let title: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            HStack(spacing: 8) {
                Image(systemName: self.iconName)
                    .font(.subheadline.weight(.bold))
                Text(self.title)
            }
            .font(.callout.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(CatalogPalette.onAccent)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(self.accent, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// 固定在安全区顶的返回与收藏：40pt 圆、卡片底、轻阴影（与库页圆按钮同一个），热区 44；爱心 20pt，已收藏实心用类型色。
/// 用法：`.safeAreaInset(edge: .top, spacing: 0)`，贴顶的分区头才会停在按钮下面而不是被按钮盖住（2026-10-08 模拟器实测）。
struct DetailTopButtons: View {
    let isFavorite: Bool
    let showsFavorite: Bool
    let accent: Color
    let backAction: () -> Void
    let favoriteAction: () -> Void

    var body: some View {
        HStack {
            Button(action: self.backAction) {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .background(CatalogPalette.cardBackground, in: Circle())
                    .shadow(color: CatalogPalette.shadow, radius: 3, y: 1)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString("Back", comment: ""))

            Spacer(minLength: 0)

            if self.showsFavorite {
                Button(action: self.favoriteAction) {
                    // 中文注释：与库页封面 / 行尾爱心同一对图。
                    Image(self.isFavorite ? "TabFavorites" : "TabFavoritesOutline")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .foregroundColor(self.isFavorite ? self.accent : Color.primary)
                        .frame(width: 40, height: 40)
                        .background(CatalogPalette.cardBackground, in: Circle())
                        .shadow(color: CatalogPalette.shadow, radius: 3, y: 1)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString(self.isFavorite ? "favorites_unfavorite" : "video_detail_favorite", comment: ""))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

/// 贴顶的章节分区头：「章节 · N 章（· 已读 M）」`headline` 主色 + 次级小字，右侧「正序 / 倒序」胶囊；下面一排分段芯片；
/// `extras` 放在芯片下面（漫画详情的受限横幅与刷新失败横幅）。
struct DetailChapterHeader<Extras: View>: View {
    let title: String
    let infoTexts: [String]
    let showsOrderToggle: Bool
    let isDescending: Bool
    let toggleOrder: () -> Void
    let segments: [ChapterSegment]
    let selectedSegmentID: String?
    let style: CatalogKindStyle
    let selectSegment: (String) -> Void
    @ViewBuilder let extras: () -> Extras

    init(
        title: String,
        infoTexts: [String],
        showsOrderToggle: Bool,
        isDescending: Bool,
        toggleOrder: @escaping () -> Void,
        segments: [ChapterSegment],
        selectedSegmentID: String?,
        style: CatalogKindStyle,
        selectSegment: @escaping (String) -> Void,
        @ViewBuilder extras: @escaping () -> Extras
    ) {
        self.title = title
        self.infoTexts = infoTexts
        self.showsOrderToggle = showsOrderToggle
        self.isDescending = isDescending
        self.toggleOrder = toggleOrder
        self.segments = segments
        self.selectedSegmentID = selectedSegmentID
        self.style = style
        self.selectSegment = selectSegment
        self.extras = extras
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(self.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                ForEach(self.infoTexts, id: \.self) { info in
                    Text(verbatim: "·")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(info)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if self.showsOrderToggle {
                    Button(action: self.toggleOrder) {
                        HStack(spacing: 4) {
                            Text(NSLocalizedString(self.isDescending ? "video_detail_order_descending" : "video_detail_order_ascending", comment: ""))
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.caption2.weight(.bold))
                        }
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(CatalogPalette.fillBackground, in: Capsule())
                        .frame(minHeight: 44)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 20)
            .padding(.top, 12)

            if self.segments.isEmpty == false {
                LibraryChipBar(
                    chips: self.segments.map { segment in
                        LibraryChipBar<String>.Chip(
                            id: segment.id,
                            title: segment.title,
                            isSelected: segment.id == self.selectedSegmentID
                        )
                    },
                    style: self.style,
                    selectAction: self.selectSegment
                )
                .padding(.top, -8)
            }

            self.extras()
        }
        .background(CatalogPalette.pageBackground)
    }
}

extension DetailChapterHeader where Extras == EmptyView {
    /// 芯片下面没有附加内容的分区头（书详情）。
    init(
        title: String,
        infoTexts: [String],
        showsOrderToggle: Bool,
        isDescending: Bool,
        toggleOrder: @escaping () -> Void,
        segments: [ChapterSegment],
        selectedSegmentID: String?,
        style: CatalogKindStyle,
        selectSegment: @escaping (String) -> Void
    ) {
        self.init(
            title: title,
            infoTexts: infoTexts,
            showsOrderToggle: showsOrderToggle,
            isDescending: isDescending,
            toggleOrder: toggleOrder,
            segments: segments,
            selectedSegmentID: selectedSegmentID,
            style: style,
            selectSegment: selectSegment,
            extras: { EmptyView() }
        )
    }
}

extension View {
    /// 贴顶时分区头停在安全区顶边，状态栏与芯片之间那一截会露出滚过的内容；底色向上多铺一段盖住，静止时藏在头部后面（头部 zIndex 更高）。
    func detailPinnedHeaderBackground() -> some View {
        self.background(alignment: .top) {
            CatalogPalette.pageBackground
                .frame(height: 160)
                .offset(y: -160)
        }
    }
}
