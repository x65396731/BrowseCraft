import BrowseCraftDomain
import SwiftUI
import UIKit

/// 规则目录页的配色与类型样式（`docs/design/Catalog-Page-Redesign-Design.md` 第三节）。
///
/// 中文注释：卡片与页面底色直接用系统分组背景，深浅色自动跟随（目录页跟随系统，与弹出它的来源页一致）；
/// 只有类型色、动作色与警示色是自定义的，深色取设计稿的值，浅色取同色相、压低明度的一组，保证白底上文字对比度不低于 4.5:1。
enum CatalogPalette {
    static let pageBackground: Color = Color(uiColor: .systemGroupedBackground)
    static let cardBackground: Color = Color(uiColor: .secondarySystemGroupedBackground)
    static let fillBackground: Color = Color(uiColor: .tertiarySystemFill)
    static let segmentBackground: Color = Color(uiColor: .tertiarySystemFill)
    static let segmentSelected: Color = Color(uiColor: .secondarySystemGroupedBackground)

    /// 添加按钮底色，白字在上面对比度满足 4.5:1。
    static let addAction: Color = Color(red: 0x25 / 255, green: 0x63 / 255, blue: 0xEB / 255)
    static let warning: Color = Self.dynamic(light: 0xC2410C, dark: 0xFF8A70)
    static let warningFill: Color = Self.dynamic(light: 0xC2410C, dark: 0xFF8A70).opacity(0.14)
    /// 反色提示条（深底浅字、浅底深字）上的动作色，例如收藏页「撤销」：浅色模式提示条是深底，用浅蓝；深色模式提示条是浅底，用添加蓝。
    static let inverseAction: Color = Self.dynamic(light: 0x8AB6FF, dark: 0x2563EB)
    /// 删除色，深浅同值（页面设计索引裁定 #E5484D）；长按菜单与确认框里的删除项由系统按 destructive 角色着色。
    static let destructive: Color = Self.fixed(0xE5484D)

    /// 不随系统深浅色变化的固定色。
    static func fixed(_ hex: UInt32) -> Color {
        return Color(uiColor: UIColor(hex: hex))
    }

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        return Color(uiColor: UIColor { traits in
            return UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

/// 每种类型的颜色、图标与横幅插画。横幅插画缺失时退回纯色底 + 图标，页面不依赖插画才能成立。
///
/// 中文注释：页面跟随系统深浅色，但**横幅永远是深色色块**——插画本身是深底，浅色页面上它就是一块深色类型色块，
/// 与来源页「正在使用」的深色类型瓷砖同一种语言（2026-10-01 用户裁定：页面之间主题色不能差异过大）。
/// 所以横幅的底色、图标圆、标题与说明文字都取固定的深色取值，不随系统变；`accent` 只给浅 / 深两种页面上的卡片用。
struct CatalogKindStyle {
    let title: String
    let symbolName: String
    /// 卡片上的类型色（徽标、标签），随系统深浅色。
    let accent: Color
    /// 横幅：固定深色取值。
    let bannerBackground: Color
    let bannerAccent: Color
    let bannerSecondaryText: Color
    /// 极梦横幅插画的资产名；资源目录里还没有这张图时 `bannerImage` 为 nil。
    let bannerAssetName: String

    var bannerImage: UIImage? {
        return UIImage(named: self.bannerAssetName)
    }

    /// 横幅上的标题与图标圆里的图形色，固定取值。
    static let bannerTitle: Color = Color(red: 0xF4 / 255, green: 0xF3 / 255, blue: 0xEF / 255)
    static let bannerIconInk: Color = Color(red: 0x14 / 255, green: 0x12 / 255, blue: 0x10 / 255)

    static func of(_ kind: CatalogSourceKind) -> CatalogKindStyle {
        switch kind {
        case .video:
            return CatalogKindStyle(
                title: NSLocalizedString("Video", comment: ""),
                symbolName: "play.fill",
                accent: CatalogPalette.dynamic(light: 0xA85A12, dark: 0xF2A65A),
                bannerBackground: CatalogPalette.fixed(0x2B2117),
                bannerAccent: CatalogPalette.fixed(0xF2A65A),
                bannerSecondaryText: CatalogPalette.fixed(0xD9C6B2),
                bannerAssetName: "CatalogBannerVideo"
            )
        case .comic:
            return CatalogKindStyle(
                title: NSLocalizedString("Comics", comment: ""),
                symbolName: "bubble.left.fill",
                accent: CatalogPalette.dynamic(light: 0x6D4FD6, dark: 0xB79CFF),
                bannerBackground: CatalogPalette.fixed(0x221E33),
                bannerAccent: CatalogPalette.fixed(0xB79CFF),
                bannerSecondaryText: CatalogPalette.fixed(0xCFC4F2),
                bannerAssetName: "CatalogBannerComic"
            )
        case .book:
            return CatalogKindStyle(
                title: NSLocalizedString("Books", comment: ""),
                symbolName: "book.closed.fill",
                accent: CatalogPalette.dynamic(light: 0x1E7D68, dark: 0x5CC8B0),
                bannerBackground: CatalogPalette.fixed(0x152A26),
                bannerAccent: CatalogPalette.fixed(0x5CC8B0),
                bannerSecondaryText: CatalogPalette.fixed(0xB6DDD3),
                bannerAssetName: "CatalogBannerBook"
            )
        }
    }
}

extension CatalogKindStyle {
    /// 来源页按已添加来源的配置取类型样式，与目录同一套取值（`docs/design/Sources-Page-Redesign-Design.md` 第三节）。
    /// 没有对应目录类型的配置（plugin）退回中性灰，不借用任何一种类型色。
    static func of(_ source: Source) -> CatalogKindStyle {
        switch source.configuration {
        case .video:
            return Self.of(CatalogSourceKind.video)
        case .comic:
            return Self.of(CatalogSourceKind.comic)
        case .book:
            return Self.of(CatalogSourceKind.book)
        case .plugin:
            return CatalogKindStyle(
                title: NSLocalizedString("sources_kind_other", comment: ""),
                symbolName: "puzzlepiece.extension.fill",
                accent: CatalogPalette.dynamic(light: 0x6B6B70, dark: 0xAEAEB2),
                bannerBackground: CatalogPalette.fixed(0x232326),
                bannerAccent: CatalogPalette.fixed(0xAEAEB2),
                bannerSecondaryText: CatalogPalette.fixed(0xC7C7CC),
                bannerAssetName: ""
            )
        }
    }
}

/// 分段切换：胶囊底上几段，选中段为卡片色底、文字加粗，可带计数徽标。目录页「推荐 | 我的生成」与收藏页类型筛选共用。
struct CatalogSegmentedPicker<Value: Hashable>: View {
    struct Segment: Identifiable {
        let value: Value
        let title: String
        var systemImage: String? = nil
        /// 为 nil 时不显示计数徽标；0 也显示。
        var count: Int? = nil

        var id: Value {
            return self.value
        }
    }

    @Binding var selection: Value
    let segments: [Segment]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(self.segments) { segment in
                self.button(segment)
            }
        }
        .padding(3)
        .background(CatalogPalette.segmentBackground, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func button(_ segment: Segment) -> some View {
        let isSelected: Bool = self.selection == segment.value
        return Button {
            self.selection = segment.value
        } label: {
            HStack(spacing: 6) {
                if let systemImage: String = segment.systemImage {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                }
                Text(segment.title)
                    .lineLimit(1)
                if let count: Int = segment.count {
                    Text(count, format: .number)
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .frame(minWidth: 20, minHeight: 20)
                        .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : .primary)
                        .background(
                            isSelected ? Color.primary : CatalogPalette.fillBackground,
                            in: Capsule()
                        )
                }
            }
            .font(.subheadline.weight(isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? .primary : .secondary)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(
                isSelected ? CatalogPalette.segmentSelected : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// 目录卡片上的文字取值：首字徽标与地址。
enum CatalogDisplayText {
    /// 站点名的第一个字符；拉丁字母取大写。
    static func monogram(for name: String) -> String {
        guard let first: Character = name.trimmingCharacters(in: .whitespacesAndNewlines).first else {
            return "·"
        }
        return String(first).uppercased()
    }

    /// 地址拆成主机名与其余部分（路径 + 查询）；解析不了时整串当主机名。
    static func addressParts(of urlString: String) -> (host: String, rest: String) {
        guard let components: URLComponents = URLComponents(string: urlString),
              let host: String = components.host, host.isEmpty == false else {
            return (host: urlString, rest: "")
        }
        var rest: String = components.percentEncodedPath
        if let query: String = components.percentEncodedQuery {
            rest += "?\(query)"
        }
        let decoded: String = rest.removingPercentEncoding ?? rest
        return (host: host, rest: decoded == "/" ? "" : decoded)
    }

    /// 推荐卡片的副标题：只显示主机名（去掉 `www.`，卡片窄）；同站多条（有各自入口）时补上路径的最后一段以便区分。
    static func recommendationSubtitle(baseURL: String, entryURL: String?) -> String {
        guard let entryURL: String = entryURL,
              let components: URLComponents = URLComponents(string: entryURL),
              let host: String = components.host, host.isEmpty == false else {
            return Self.displayHost(Self.addressParts(of: baseURL).host)
        }
        let lastPathComponent: String = components.path.split(separator: "/").last.map(String.init) ?? ""
        let tail: String = lastPathComponent + (components.query.map { "?\($0)" } ?? "")
        return tail.isEmpty ? Self.displayHost(host) : "\(Self.displayHost(host)) · \(tail)"
    }

    static func displayHost(_ host: String) -> String {
        return host.lowercased().hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
