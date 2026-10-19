import SwiftUI

// 中文注释：两个入口的小组件（docs/design/Problem-Report-Design.md 第三节，`BCA-UI-006`）：
// 失败态上的动作蓝小字链接（不做成与「重试」同级的按钮），以及页面「…」圆按钮里的「报告这一页的问题」。

/// 失败态入口：一行动作蓝小字「报告问题」。
struct ProblemReportLink: View {
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            Text(NSLocalizedString("problem_report_link", comment: "失败态入口：报告问题"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(CatalogPalette.addAction)
                .frame(minHeight: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 常驻入口：40pt 卡片底色圆按钮「…」，点开是系统菜单，目前只有「报告这一页的问题」一项。
struct ProblemReportMenuButton: View {
    /// 中文注释：影视详情的深色头图区用半透明深底、浅色图形，与旁边的返回、收藏圆按钮一致。
    var onDark: Bool = false
    let action: () -> Void

    var body: some View {
        Menu {
            Button(action: self.action) {
                Label(
                    NSLocalizedString("problem_report_menu_item", comment: "常驻入口：报告这一页的问题"),
                    systemImage: "exclamationmark.bubble"
                )
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.headline.weight(.semibold))
                .foregroundStyle(self.onDark ? CatalogKindStyle.bannerTitle : Color.primary)
                .frame(width: 40, height: 40)
                .background(self.onDark ? CatalogPalette.onDarkFill : CatalogPalette.cardBackground, in: Circle())
                .shadow(color: self.onDark ? Color.clear : CatalogPalette.shadow, radius: 3, y: 1)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(NSLocalizedString("problem_report_menu_label", comment: "读屏：更多"))
    }
}
