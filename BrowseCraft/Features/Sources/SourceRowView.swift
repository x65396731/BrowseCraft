import BrowseCraftDomain
import SwiftUI

// 中文注释：来源页的组件（`docs/design/Sources-Page-Redesign-Design.md` 方案 A）：来源行、正在使用卡片与来源位置条。
// 颜色全部取 `CatalogStyle.swift`，与从来源页弹出的规则目录页同一套，不另起一套。

/// 来源页上一行的文字取值。
enum SourceDisplayText {
    /// 「类型 · 出身 · 主机名」；`includesHost` 为 false 时只到出身（已暂停区与启用窗口）。
    static func subtitle(for source: Source, includesHost: Bool = true) -> String {
        var parts: [String] = [
            CatalogKindStyle.of(source).title,
            Self.origin(of: source)
        ]
        if includesHost {
            let host: String = CatalogDisplayText.addressParts(of: source.baseURL).host
            parts.append(CatalogDisplayText.displayHost(host))
        }
        return parts.joined(separator: " · ")
    }

    /// 出身：本人生成的为「我的生成」，其余都经公共目录到达（`BCA-UI-003`），为「来自目录」。
    static func origin(of source: Source) -> String {
        if source.isBuiltIn {
            return NSLocalizedString("Built-in source", comment: "")
        }
        if source.origin == .personalGeneration {
            return NSLocalizedString("catalog_section_personal", comment: "")
        }
        return NSLocalizedString("sources_origin_catalog", comment: "")
    }
}

/// 「其他来源」与「已暂停」里的一行。同一组的行拼成一张圆角卡片：首行圆上角、末行圆下角，行间一条细线。
struct SourceRowView: View {
    enum Role {
        /// 可切换的其他来源；`isSwitching` 为正在加载第一页的那一行。
        case other(isSwitching: Bool)
        /// 因位置不够被锁定；`canActivateWithoutReplacement` 决定按钮写「启用」还是「替换使用」。
        case paused(canActivateWithoutReplacement: Bool)
    }

    let source: Source
    let role: Role
    let isFirst: Bool
    let isLast: Bool
    let action: () -> Void

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Button(action: self.action) {
            HStack(spacing: 12) {
                self.leading
                VStack(alignment: .leading, spacing: 3) {
                    Text(self.source.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(self.isPaused ? .secondary : .primary)
                        .lineLimit(1)
                    Text(self.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(self.isSwitching ? 2 : 1)
                }
                Spacer(minLength: 8)
                self.trailing
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    CatalogPalette.cardBackground
                    if self.isSwitching {
                        CatalogPalette.addAction.opacity(0.12)
                    }
                }
            }
            .overlay(alignment: .top) {
                if self.isFirst == false {
                    Rectangle()
                        .fill(CatalogPalette.separator)
                        .frame(height: 1 / self.displayScale)
                        .padding(.leading, 68)
                }
            }
            .clipShape(self.shape)
            .contentShape(.interaction, self.shape)
            .contentShape(.contextMenuPreview, self.shape)
        }
        .buttonStyle(.plain)
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

    private var isPaused: Bool {
        if case .paused = self.role {
            return true
        }
        return false
    }

    private var isSwitching: Bool {
        if case .other(let isSwitching) = self.role {
            return isSwitching
        }
        return false
    }

    private var subtitle: String {
        if self.isSwitching {
            return NSLocalizedString("sources_switching_message", comment: "")
        }
        return SourceDisplayText.subtitle(for: self.source, includesHost: self.isPaused == false)
    }

    @ViewBuilder
    private var leading: some View {
        if self.isPaused {
            Image(systemName: "lock")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 42, height: 42)
                .background(CatalogPalette.fillBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
        } else {
            CatalogMonogramView(name: self.source.name, accent: CatalogKindStyle.of(self.source).accent, size: 42)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch self.role {
        case .other(let isSwitching):
            if isSwitching {
                ProgressView()
            } else {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        case .paused(let canActivateWithoutReplacement):
            // 中文注释：整行就是按钮，这里只是它的视觉标签；两种写法都打开启用来源窗口（2.4）。
            let color: Color = canActivateWithoutReplacement ? CatalogPalette.addAction : CatalogPalette.warning
            Text(
                NSLocalizedString(
                    canActivateWithoutReplacement ? "sources_paused_activate" : "sources_paused_replace",
                    comment: ""
                )
            )
            .font(.footnote.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .overlay(Capsule().strokeBorder(color, lineWidth: 1))
        }
    }
}

/// 正在使用的来源：类型色深色瓷砖，取值与规则目录的类型横幅相同，固定深色、不随系统变（2.2）。
struct SourceInUseCardView: View {
    let source: Source
    let action: () -> Void

    var body: some View {
        let style: CatalogKindStyle = CatalogKindStyle.of(self.source)
        Button(action: self.action) {
            VStack(alignment: .leading, spacing: 16) {
                SourceTileBadgeView(
                    title: NSLocalizedString("sources_in_use_badge", comment: ""),
                    systemImage: "checkmark",
                    foreground: CatalogKindStyle.bannerIconInk,
                    background: style.bannerAccent
                )
                SourceTileIdentityView(
                    name: self.source.name,
                    subtitle: SourceDisplayText.subtitle(for: self.source),
                    style: style
                )
                HStack {
                    Text(NSLocalizedString("sources_in_use_open_hint", comment: ""))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .fontWeight(.semibold)
                }
                .font(.footnote)
                .foregroundStyle(style.bannerSecondaryText)
            }
            .sourceTile(style: style)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(format: NSLocalizedString("sources_in_use_accessibility", comment: ""), self.source.name)
        )
        .accessibilityAddTraits(.isButton)
    }
}

/// 深色瓷砖上的徽章：「正在使用」或「已暂停 · 类型」。
struct SourceTileBadgeView: View {
    let title: String
    let systemImage: String
    let foreground: Color
    let background: Color

    var body: some View {
        Label(self.title, systemImage: self.systemImage)
            .font(.caption.weight(.bold))
            .labelStyle(SourceTightLabelStyle())
            .foregroundStyle(self.foreground)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(self.background, in: Capsule())
    }
}

/// 深色瓷砖上的首字徽标 + 站点名 + 副标题。
struct SourceTileIdentityView: View {
    let name: String
    let subtitle: String
    let style: CatalogKindStyle

    var body: some View {
        HStack(spacing: 14) {
            CatalogMonogramView(name: self.name, accent: self.style.bannerAccent, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(self.name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(CatalogKindStyle.bannerTitle)
                    .lineLimit(2)
                Text(self.subtitle)
                    .font(.footnote)
                    .foregroundStyle(self.style.bannerSecondaryText)
                    .lineLimit(1)
            }
        }
    }
}

extension View {
    /// 类型色深色瓷砖：横幅底色 + 右上光圈，圆角 24。
    func sourceTile(style: CatalogKindStyle) -> some View {
        return self
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack(alignment: .topTrailing) {
                    style.bannerBackground
                    Circle()
                        .fill(style.bannerAccent.opacity(0.25))
                        .frame(width: 160, height: 160)
                        .offset(x: 30, y: -30)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// 图标与文字之间只留 4pt 的标签样式（徽章用）。
private struct SourceTightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}

/// 来源位置条：「已用来源位置」与「已用 / 上限」，下面一条进度条；最右「更多位置」进入高级版购买（2.1）。
/// iCloud 首次恢复时没有可信的数字，`used` / `limit` 为 nil，显示「— / —」与空进度条。
struct SourceSlotBarView: View {
    let used: Int?
    let limit: Int?
    let moreAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 6) {
                HStack {
                    Text(NSLocalizedString("sources_slots_used", comment: ""))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(self.valueText)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundStyle(self.used == nil ? .tertiary : .primary)
                }
                .font(.footnote)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(NSLocalizedString("sources_slots_used", comment: ""))
                .accessibilityValue(self.valueText)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(CatalogPalette.fillBackground)
                        Capsule()
                            .fill(Color.primary)
                            .frame(width: proxy.size.width * self.fraction)
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
            }

            if let moreAction: () -> Void = self.moreAction {
                Button(NSLocalizedString("sources_slots_more", comment: "")) {
                    moreAction()
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(CatalogPalette.addAction)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, self.moreAction == nil ? 12 : 4)
        .background(CatalogPalette.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var valueText: String {
        guard let used: Int = self.used, let limit: Int = self.limit else {
            return "— / —"
        }
        return "\(used) / \(limit)"
    }

    private var fraction: CGFloat {
        guard let used: Int = self.used, let limit: Int = self.limit, limit > 0 else {
            return 0
        }
        return min(1, CGFloat(used) / CGFloat(limit))
    }
}
