import BrowseCraftDomain
import SwiftUI

/// 库页的分类条：横向滚动的胶囊芯片，选中段用来源类型色底（`docs/design/Library-Video-Page-Redesign-Design.md` 第五节）。
///
/// 中文注释：三种类型共用这一份，换 `CatalogKindStyle` 即换色——此前 video / comic / default 各写一份几乎相同的芯片代码，
/// 选中色是写死的蓝紫。它作为 `LazyVStack` 的 pinned 分区头贴顶，所以自带页面底色。
struct LibraryListTabBar: View {
    let source: Source?
    let tabs: [LibraryListTabState]
    let isInteractionDisabled: Bool
    let selectAction: (String) async -> Void

    @Environment(\.colorScheme) private var colorScheme: ColorScheme

    var body: some View {
        // 中文注释：2026-09-23 用户裁定 video / comic 不再生成分类标签——入口只接受「全部」类列表页，
        // 规则只有一个列表，其余内容靠搜索找到。只有一个列表时标签只是一个不可切换的按钮，不显示；
        // 多个列表页（旧来源的分类，或 BC-PAGE-063 由入口页推导的同组标签）照常显示。
        if self.tabs.count <= 1 {
            EmptyView()
        } else {
            self.chipBar
        }
    }

    private var chipBar: some View {
        let style: CatalogKindStyle? = self.source.map { CatalogKindStyle.of($0) }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(self.tabs) { tab in
                    Button(
                        action: {
                            Task {
                                await self.selectAction(tab.id)
                            }
                        },
                        label: {
                            Text(tab.title)
                                .font(.subheadline.weight(tab.isSelected ? .semibold : .medium))
                                .lineLimit(1)
                                .foregroundStyle(self.textColor(isSelected: tab.isSelected, style: style))
                                .padding(.horizontal, 16)
                                .frame(minHeight: 36)
                                .background(
                                    tab.isSelected
                                        ? (style?.accent ?? Color.primary)
                                        : CatalogPalette.fillBackground,
                                    in: Capsule()
                                )
                                .contentShape(Capsule())
                        }
                    )
                    .buttonStyle(.plain)
                    .disabled(self.isInteractionDisabled)
                    .accessibilityAddTraits(tab.isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(CatalogPalette.pageBackground)
    }

    /// 选中段：浅色是深琥珀底配白字，深色是浅琥珀底配墨字，两者对比度都不低于 4.5:1。
    private func textColor(isSelected: Bool, style: CatalogKindStyle?) -> Color {
        guard isSelected else {
            return .primary
        }
        guard style != nil else {
            return Color(uiColor: .systemBackground)
        }
        return self.colorScheme == .dark ? CatalogKindStyle.bannerIconInk : .white
    }
}
