import SwiftUI

// 中文注释：收藏页与历史页选择模式共用的零件（`docs/design/Favorites-Page-Redesign-Design.md` 2.5、
// `docs/design/History-Page-Redesign-Design.md` 2.6）：行首勾选框、标题行按钮、替换底栏的操作栏。
// 取值都来自 `CatalogStyle.swift`，这里不声明颜色。

/// 行首 24pt 圆形勾选框：选中为添加蓝底白勾，未选为灰色圆环。
struct ContentSelectionMark: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            if self.isSelected {
                Circle()
                    .fill(CatalogPalette.addAction)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CatalogPalette.onAction)
            } else {
                Circle()
                    .strokeBorder(CatalogPalette.tertiaryText, lineWidth: 2)
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}

/// 标题行右侧的小胶囊按钮：「选择」是填充色底 + 添加蓝字，「完成」是实心添加蓝。
/// 胶囊高 32，触控区补到 44。
struct ContentHeaderButton: View {
    enum Style {
        case plain
        case prominent
    }

    let title: String
    var style: Style = .plain
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: self.action) {
            Text(self.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(self.style == .prominent ? CatalogPalette.onAction : CatalogPalette.settingsIcon)
                .padding(.horizontal, self.style == .prominent ? 16 : 14)
                .frame(height: 32)
                .background(
                    self.style == .prominent ? CatalogPalette.addAction : CatalogPalette.fillBackground,
                    in: Capsule()
                )
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(self.isEnabled ? 1 : 0.4)
    }
}

/// 选择模式下替换底栏的操作栏：「全选 / 全不选」、已选数量、红色操作按钮（一条没选时禁用）。
struct ContentSelectionBar: View {
    let selectAllTitle: String
    let countText: String
    let actionTitle: String
    let actionSystemImage: String
    let isActionEnabled: Bool
    let selectAllAction: () -> Void
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(self.selectAllTitle, action: self.selectAllAction)
                .font(.body.weight(.semibold))
                .foregroundStyle(CatalogPalette.settingsIcon)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .buttonStyle(.plain)

            Spacer(minLength: 8)

            Text(self.countText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button(action: self.action) {
                Label(self.actionTitle, systemImage: self.actionSystemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CatalogPalette.onAction)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(CatalogPalette.destructive, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(self.isActionEnabled == false)
            .opacity(self.isActionEnabled ? 1 : 0.4)
        }
        .padding(.leading, 22)
        .padding(.trailing, 10)
        .frame(height: 64)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: CatalogPalette.shadow, radius: 9, y: 4)
    }
}
