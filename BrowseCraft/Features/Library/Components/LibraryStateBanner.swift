import SwiftUI

/// 库页、三个详情页与来源内搜索页共用的页内横幅：警示色淡底、圆角 16，左图标、中一句说明、右侧按钮。
/// 2026-10-10 复审第七批把三页各画一份的横幅收成这一个，颜色统一走警示色系（与原 `LibraryTabErrorBanner` 同一语言），
/// 类型色留给内容区的芯片与开始按钮，三种 kind 的横幅长得一样。两种状态：
/// - `.failure`（取失败 / 搜索失败）：三角图标；右侧「重试」警示色实心；来源有登录页时左边多一个「登录」警示色描边；没有关闭。
/// - `.restricted`（受限章节 / 登录提示）：锁图标；右侧「登录」警示色实心；带关闭叉。
/// 只给 `message` 时就是库页「有内容但本分类报错」的纯文字横幅（各库页合同「其余状态」一节）。
struct LibraryStateBanner: View {
    enum Kind {
        case failure
        case restricted
    }

    let kind: Kind
    let message: String
    var loginAction: (() -> Void)? = nil
    var retryAction: (() -> Void)? = nil
    var dismissAction: (() -> Void)? = nil

    var body: some View {
        if self.hasControls {
            self.content
        } else {
            self.content
                .accessibilityElement(children: .combine)
        }
    }

    private var hasControls: Bool {
        return self.loginAction != nil || self.retryAction != nil || self.dismissAction != nil
    }

    private var iconName: String {
        switch self.kind {
        case .failure:
            return "exclamationmark.triangle.fill"
        case .restricted:
            return "lock.fill"
        }
    }

    private var content: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: self.iconName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CatalogPalette.warning)
                .accessibilityHidden(true)

            Text(self.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 中文注释：最右边的那个动作按钮实心，其余描边——失败态是「登录（描边）重试（实心）」，受限态只有「登录（实心）」。
            if let loginAction: () -> Void = self.loginAction {
                self.actionButton(
                    NSLocalizedString("library_banner_login", comment: ""),
                    filled: self.retryAction == nil,
                    action: loginAction
                )
            }
            if let retryAction: () -> Void = self.retryAction {
                self.actionButton(NSLocalizedString("library_banner_retry", comment: ""), filled: true, action: retryAction)
            }
            if let dismissAction: () -> Void = self.dismissAction {
                Button(action: dismissAction) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("library_banner_dismiss", comment: ""))
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, self.dismissAction == nil ? 14 : 4)
        .padding(.vertical, self.hasControls ? 8 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CatalogPalette.warningFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func actionButton(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(filled ? Color.white : CatalogPalette.warning)
                .padding(.horizontal, 12)
                .frame(minHeight: 30)
                .background(filled ? CatalogPalette.warning : Color.clear, in: Capsule())
                .overlay(Capsule().strokeBorder(CatalogPalette.warning, lineWidth: filled ? 0 : 1))
                .frame(minHeight: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
