import SwiftUI

// 中文注释：设置页的行与卡片组（`docs/design/Settings-Page-Redesign-Design.md` 第四节）。
// 标题一律主文字色——能不能点靠 › 与按下态表达，不靠控件类型的默认着色。

/// 32pt 图标方块：添加蓝底 + 资产里的 `Settings*` 模板图。
struct SettingsIconTile: View {
    /// 资产目录里的模板图名（Settings*.imageset，22pt 纯黑剪影），按 pt 原生渲染、不经 `.resizable()`。
    let image: String

    var body: some View {
        Image(self.image)
            .foregroundStyle(CatalogPalette.settingsIcon)
            .frame(width: 32, height: 32)
            .background(CatalogPalette.settingsIconFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct SettingsRow: View {
    enum Accessory {
        case none
        case chevron
    }

    let image: String
    let title: String
    var detail: String? = nil
    /// 「已复制」这类瞬时反馈用图标色强调。
    var isDetailHighlighted: Bool = false
    var accessory: Accessory = .none

    var body: some View {
        HStack(spacing: 12) {
            SettingsIconTile(image: self.image)

            Text(self.title)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 8)

            if let detail: String = self.detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(self.isDetailHighlighted ? CatalogPalette.settingsIcon : Color.secondary)
                    .lineLimit(1)
            }

            if self.accessory == .chevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

/// 行尾是系统开关的一行；开关用系统默认样式。
struct SettingsToggleRow: View {
    let image: String
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: self.$isOn) {
            HStack(spacing: 12) {
                SettingsIconTile(image: self.image)
                Text(self.title)
                    .font(.body)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 52)
    }
}

/// 卡片组：分组标题 + 圆角 18 的卡片 + 可选的组下说明。行之间用 `SettingsRowSeparator`。
struct SettingsCardGroup<Content: View>: View {
    let title: String?
    var footer: String? = nil
    /// 中文注释：组下说明的颜色；默认次级灰，添加来源页未登录那句用警示色（合同第三节）。
    var footerColor: Color? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title: String = self.title {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
                    .padding(.top, 22)
                    .padding(.bottom, 8)
                    .accessibilityAddTraits(.isHeader)
            }

            VStack(spacing: 0) {
                self.content
            }
            .background(CatalogPalette.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 20)

            if let footer: String = self.footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(self.footerColor ?? Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
            }
        }
    }
}

/// 卡片组里的行间线：从 60pt 起（左边距 16 + 图标 32 + 间距 12），与图标右侧的文字对齐。
struct SettingsRowSeparator: View {
    var leadingInset: CGFloat = 60

    var body: some View {
        Divider()
            .padding(.leading, self.leadingInset)
    }
}

/// 卡片里可点的行：按下时铺一层系统填充色，代替列表的选中高亮。
struct SettingsRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? CatalogPalette.pressedFill : Color.clear)
    }
}
