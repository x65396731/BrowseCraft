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
    /// 获得色：coin 记录里的 +N（`docs/design/Coin-Ledger-Page-Redesign-Design.md`，用户裁定用绿）。
    /// 浅色不取系统绿 #34C759——它在白底上做文字对比度不到 4.5:1。
    static let gain: Color = Self.dynamic(light: 0x248A3D, dark: 0x30D158)
    /// 设置页行图标（`docs/design/Settings-Page-Redesign-Design.md` 第四节）：浅色取添加蓝；深色底上添加蓝看不清，取 `inverseAction` 的浅蓝。
    static let settingsIcon: Color = Self.dynamic(light: 0x2563EB, dark: 0x8AB6FF)
    /// 设置页行图标方块的底：添加蓝，浅色 12%、深色 24%。
    static let settingsIconFill: Color = Color(uiColor: UIColor { traits in
        return UIColor(hex: 0x2563EB).withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.24 : 0.12)
    })

    /// 流光点阵的多彩渐变（`docs/design/Generation-Input-Page-Redesign-Design.md` 第三节，用户 2026-10-07 裁定 A）：
    /// 沿轨道浅蓝 → 薰衣草 → 浅粉 → 杏色的粉彩，深浅同值（用户 2026-10-07 看参考图后要求比饱和版淡）；
    /// 右端落在困难档琥珀附近，所以档位滑杆拖到困难时自然变「暖」。
    static let spectrumStops: [UInt32] = [0x7FA8F7, 0xB9A3F5, 0xF2A8C8, 0xF8C38F]

    /// 渐变的四个色标，按顺序；给描边、文字、滑块用横向 `LinearGradient`（用户 2026-10-07 裁定：困难档不要黄色，用多彩）。
    static var spectrumColors: [Color] {
        return Self.spectrumStops.map { Self.fixed($0) }
    }

    static var spectrumGradient: LinearGradient {
        return LinearGradient(colors: Self.spectrumColors, startPoint: .leading, endPoint: .trailing)
    }

    /// 饱和版渐变：给压在粉彩点阵上的文字、滑块与描边用——粉彩字压粉彩点读不清（2026-10-07 模拟器实测）。
    static let spectrumVividStops: [UInt32] = [0x2563EB, 0x7C3AED, 0xE0457B, 0xF28C28]

    static var spectrumVividColors: [Color] {
        return Self.spectrumVividStops.map { Self.fixed($0) }
    }

    static var spectrumVividGradient: LinearGradient {
        return LinearGradient(colors: Self.spectrumVividColors, startPoint: .leading, endPoint: .trailing)
    }

    /// 渐变的淡底（16%），给困难按钮与困难档滑动确认的底。
    static var spectrumFill: LinearGradient {
        return LinearGradient(colors: Self.spectrumColors.map { $0.opacity(0.16) }, startPoint: .leading, endPoint: .trailing)
    }

    /// 渐变上某一点的颜色，`position` 0 … 1 从左到右；在 RGB 里线性插值（iOS 17 没有 `Color.mix`）。
    static func spectrumColor(at position: CGFloat) -> Color {
        let stops: [UInt32] = Self.spectrumStops
        let clamped: CGFloat = min(1, max(0, position))
        let scaled: CGFloat = clamped * CGFloat(stops.count - 1)
        let index: Int = min(stops.count - 2, Int(scaled))
        let fraction: CGFloat = scaled - CGFloat(index)
        let from: UInt32 = stops[index]
        let to: UInt32 = stops[index + 1]
        func channel(_ shift: UInt32) -> Double {
            let a: CGFloat = CGFloat((from >> shift) & 0xFF)
            let b: CGFloat = CGFloat((to >> shift) & 0xFF)
            return Double(a + (b - a) * fraction) / 255
        }
        return Color(red: channel(16), green: channel(8), blue: channel(0))
    }

    // MARK: - 2026-10-11 颜色收敛（复审「Features 层约 60 处颜色绕过 CatalogStyle」）：下面这组按角色命名，页面里不再直接写 .white / .black / Color(uiColor:)。
    // 仍允许直接写颜色的只有功能性取值，与内购页固定深色同一类，逐处有注释：漫画阅读器页面底（ReaderPageImageView）、
    // 播放器黑底（Video/Player）、启动动画（StartupAnimationView）、调试页（SourceDebugView）、Apple 登录按钮的系统样式、
    // 设置页全屏广告位的黑底、流光描边两端夹的白光。

    /// 实心动作按钮（添加蓝、警示色实心、固定深色底）上的文字与图标：白，深浅同值。
    static let onAction: Color = .white
    /// 类型色 `accent` 底上的文字与图标：浅色白、深色墨——accent 在深色里是浅色调（原各页 `colorScheme == .dark ? bannerIconInk : .white`）。
    static let onAccent: Color = Self.dynamic(light: 0xFFFFFF, dark: 0x141210)
    /// 以 `.primary` 为底的反色元素（反色提示条、卡片徽章、来源页空状态的「用网址生成」图标圆）上的文字：系统背景色。
    static let onPrimary: Color = Color(uiColor: .systemBackground)
    /// 非分组的页面底：登录页、阅读器、临时资源页、库页分类条贴顶时的底。
    static let plainBackground: Color = Color(uiColor: .systemBackground)
    /// 分隔线。
    static let separator: Color = Color(uiColor: .separator)
    /// 三级文字：目录卡片地址的路径部分。
    static let tertiaryText: Color = Color(uiColor: .tertiaryLabel)
    /// 行按下态的底（设置页行）。
    static let pressedFill: Color = Color(uiColor: .systemFill)
    /// 彩色卡片按下时盖的一层（黑 25%）；不按时用 `.opacity(0)`。
    static let pressedScrim: Color = Color.black.opacity(0.25)
    /// 圆按钮的轻阴影（黑 8%，半径 3、偏移 1）。
    static let shadow: Color = Color.black.opacity(0.08)
    /// 卡片与封面的重阴影（黑 18%）。
    static let cardShadow: Color = Color.black.opacity(0.18)
    /// 固定深色头图上海报的投影（黑 35%）。
    static let posterShadow: Color = Color.black.opacity(0.35)
    /// 封面上爱心 / 耳机小圆的底（黑 40%）。
    static let coverScrim: Color = Color.black.opacity(0.4)
    /// 封面底边或书脊的渐暗（黑 18%）。
    static let coverShade: Color = Color.black.opacity(0.18)
    /// 封面角上类型徽章的底（黑 28%）。
    static let badgeScrim: Color = Color.black.opacity(0.28)
    /// 影视详情模糊海报头图上压的一层（黑 45%）。
    static let headerScrim: Color = Color.black.opacity(0.45)
    /// 固定深色瓷砖 / 头图上的半透明白：进度条轨道、圆按钮底、徽章底，统一 16%（原各处 14% / 16% / 18%）。
    static let onDarkFill: Color = Color.white.opacity(0.16)

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

/// 类型横幅：固定深色类型底 + 右侧横幅插画，左下图标圆 + 类型名 + 一句副标题；高 112，圆角 22。
/// 规则目录页用它做每类的分区头（副标题「左右滑动查看全部」）；添加来源页用它做三张可点的类型卡
/// （副标题是举例、类型名后带 ›，`docs/design/Add-Source-Page-Redesign-Design.md` 第三节）。
/// 缺插画时退回纯色底 + 图标，页面不依赖插画才能成立。
struct CatalogKindBannerView: View {
    let style: CatalogKindStyle
    let subtitle: String
    /// 类型名后带 ›，表示整张横幅可点。
    var showsChevron: Bool = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // 中文注释：插画挂成底色的 overlay 而不是 ZStack 的一层——1200×336 的图按 112pt 高 scaledToFill 后宽 400pt，
            // 比小屏上 362pt 的可用宽度大；放进 ZStack 会把横幅的布局宽度撑到 400，整列内容随之比屏幕宽、左右边距消失
            // （添加来源页 2026-10-06 真机截图）。overlay 不参与布局尺寸，溢出的部分由下面的圆角裁掉。
            self.style.bannerBackground
                .overlay {
                    if let image: UIImage = self.style.bannerImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .accessibilityHidden(true)
                    }
                }
            HStack(spacing: 12) {
                Image(systemName: self.style.symbolName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CatalogKindStyle.bannerIconInk)
                    .frame(width: 40, height: 40)
                    .background(self.style.bannerAccent, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(self.style.title)
                            .font(.title2.weight(.heavy))
                            .foregroundStyle(CatalogKindStyle.bannerTitle)
                        if self.showsChevron {
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(self.style.bannerAccent)
                                .accessibilityHidden(true)
                        }
                    }
                    Text(self.subtitle)
                        .font(.caption)
                        .foregroundStyle(self.style.bannerSecondaryText)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .frame(height: 112)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
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
