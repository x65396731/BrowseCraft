import BrowseCraftDomain
import SwiftUI

/// 胶囊芯片条：横向滚动，选中段用类型色底（`docs/design/Library-Video-Page-Redesign-Design.md` 第五节）。
/// 库页分类条与影视详情页的线路芯片共用（`docs/design/Video-Detail-Page-Redesign-Design.md` 第六节）；
/// 换 `CatalogKindStyle` 即换色，不为每种类型写一份。
struct LibraryChipBar<ID: Hashable>: View {
    struct Chip: Identifiable {
        let id: ID
        let title: String
        let isSelected: Bool
    }

    let chips: [Chip]
    /// nil（plugin 来源）时选中段用主文字色反色。
    let style: CatalogKindStyle?
    var isInteractionDisabled: Bool = false
    /// 贴顶时自带页面底色；嵌在卡片里时传 `.clear`。
    var background: Color = CatalogPalette.pageBackground
    let selectAction: (ID) -> Void


    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(self.chips) { chip in
                    Button(
                        action: {
                            self.selectAction(chip.id)
                        },
                        label: {
                            Text(chip.title)
                                .font(.subheadline.weight(chip.isSelected ? .semibold : .medium))
                                .lineLimit(1)
                                .foregroundStyle(self.textColor(isSelected: chip.isSelected))
                                .padding(.horizontal, 16)
                                .frame(minHeight: 36)
                                .background(
                                    chip.isSelected
                                        ? (self.style?.accent ?? Color.primary)
                                        : CatalogPalette.fillBackground,
                                    in: Capsule()
                                )
                                .contentShape(Capsule())
                        }
                    )
                    .buttonStyle(.plain)
                    .disabled(self.isInteractionDisabled)
                    .accessibilityAddTraits(chip.isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(self.background)
    }

    /// 选中段：浅色是深琥珀底配白字，深色是浅琥珀底配墨字，两者对比度都不低于 4.5:1。
    private func textColor(isSelected: Bool) -> Color {
        guard isSelected else {
            return .primary
        }
        guard self.style != nil else {
            return CatalogPalette.plainBackground
        }
        return CatalogPalette.onAccent
    }
}

/// 库页的分类条：来源有两个以上列表页时显示，作为 `LazyVStack` 的 pinned 分区头贴顶。
struct LibraryListTabBar: View {
    let source: Source?
    let tabs: [LibraryListTabState]
    let isInteractionDisabled: Bool
    let selectAction: (String) async -> Void

    var body: some View {
        // 中文注释：2026-09-23 用户裁定 video / comic 不再生成分类标签——入口只接受「全部」类列表页，
        // 规则只有一个列表，其余内容靠搜索找到。只有一个列表时标签只是一个不可切换的按钮，不显示；
        // 多个列表页（旧来源的分类，或 BC-PAGE-063 由入口页推导的同组标签）照常显示。
        if self.tabs.count <= 1 {
            EmptyView()
        } else {
            LibraryChipBar(
                chips: self.tabs.map { tab in
                    LibraryChipBar<String>.Chip(id: tab.id, title: tab.title, isSelected: tab.isSelected)
                },
                style: self.source.map { CatalogKindStyle.of($0) },
                isInteractionDisabled: self.isInteractionDisabled,
                selectAction: { tabID in
                    Task {
                        await self.selectAction(tabID)
                    }
                }
            )
        }
    }
}
