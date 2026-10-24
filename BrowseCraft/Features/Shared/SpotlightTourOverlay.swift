import SwiftUI

// 中文注释：SpotlightTourOverlay.swift 属于界面功能层的共用组件，承载新手引导的「聚光灯气泡层」
// （`docs/design/Onboarding-Design.md` 第三节）。它不持有任何页面逻辑（`BCA-UI-009`）：页面用 `spotlightTarget`
// 登记目标矩形，这一层只按当前步画蒙层、挖空与气泡；请用户点的那一步把挖空区的点击放行，控件的原动作照常执行。
// 2026-10-24 v2 视觉（第八节，用户六项裁定全取 A）：蒙层墨青调，挖空多彩渐变描边 + 外发光，气泡带三段进度条、
// 墨青圆图标、小标题与墨青实心按钮，欢迎卡上半段是墨青色块 + 海报帧 + 类型胶囊，「开始」多彩渐变胶囊；不用系统蓝。

/// 页面上可被聚光的目标。
enum SpotlightTarget: Hashable, Sendable {
    /// 来源页空状态块（插画 + 「还没有来源」+ 一句说明）。
    case sourcesEmptyState
    /// 来源页「正在使用」卡（回看时第 1 步的备选）。
    case sourcesInUseCard
    /// 来源页空状态的两张入口卡（一个挖空包住两张）。
    case sourcesEntryCards
    /// 来源页右上「✦ 目录 | ＋ 添加」胶囊（回看时第 3 步的备选）。
    case sourcesActionCapsule
    /// 库页第一张海报 / 封面 / 书脊行。
    case libraryFirstCover
}

/// 目标矩形的汇集：各页面登记的 Anchor，根视图用 `overlayPreferenceValue` 读。同一目标登记了多次时取最先的。
struct SpotlightAnchorKey: PreferenceKey {
    static let defaultValue: [SpotlightTarget: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [SpotlightTarget: Anchor<CGRect>],
        nextValue: () -> [SpotlightTarget: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { current, _ in
            return current
        }
    }
}

extension View {
    /// 登记这个视图为聚光目标；`isActive` 为假时不登记（网格里只有第一张卡登记）。
    func spotlightTarget(_ target: SpotlightTarget, isActive: Bool = true) -> some View {
        return self.anchorPreference(key: SpotlightAnchorKey.self, value: .bounds) { anchor in
            return isActive ? [target: anchor] : [:]
        }
    }
}

/// 一步聚光落在哪里：页面登记的目标（可带备选）、底栏、或没有目标（欢迎卡）。
enum SpotlightTourFocus: Equatable {
    case anchor(SpotlightTarget, fallback: SpotlightTarget?)
    /// 底栏不是 SwiftUI 子视图，矩形按安全区底部 + 49pt 算。
    case tabBar
    case none
}

/// 气泡正文左侧的图标（第四节）：墨青圆 + 青绿线性符号。
enum SpotlightTourIcon: Equatable {
    case globe
    case tabs
    case plus
    case heart

    var systemName: String {
        switch self {
        case .globe:
            return "globe"
        case .tabs:
            return "rectangle.bottomthird.inset.filled"
        case .plus:
            return "plus"
        case .heart:
            return "heart"
        }
    }
}

/// 步号行的三段进度条：第几步、共几步。
struct SpotlightTourProgress: Equatable {
    let index: Int
    let total: Int
}

/// 引导层的一步：目标、文案与结束方式。
struct SpotlightTourStep: Equatable {
    enum Mode: Equatable {
        /// 欢迎卡：标题 + 正文 + 主按钮 + 文字按钮「跳过」，整屏蒙层没有挖空。
        case welcome(title: String, primaryTitle: String)
        /// 气泡 + 一个按钮（「下一步」/「知道了」）。
        case bubble(buttonTitle: String)
        /// 气泡 + 一句提示，没有按钮；挖空区的点击透过去。
        case tapThrough(hint: String)
    }

    let id: String
    let focus: SpotlightTourFocus
    /// 三段进度条，欢迎卡与库页那一步没有。
    let progress: SpotlightTourProgress?
    /// 步号「1 / 3」，欢迎卡与库页那一步没有。
    let counter: String?
    /// 气泡小标题，欢迎卡没有（它有自己的标题）。
    let heading: String?
    /// 气泡图标，欢迎卡没有。
    let icon: SpotlightTourIcon?
    let message: String
    let mode: Mode
    /// 挖空圆角：目标圆角 + 4。
    let cornerRadius: CGFloat
}

/// 蒙层 + 挖空 + 气泡（步号行右侧带「跳过」）。盖在根视图的 `TabView` 上，`ignoresSafeArea` 含底栏。
struct SpotlightTourOverlay: View {
    let step: SpotlightTourStep
    let anchors: [SpotlightTarget: Anchor<CGRect>]
    let skipTitle: String
    let primaryAction: () -> Void
    let skipAction: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool
    @Environment(\.colorScheme) private var colorScheme: ColorScheme

    private static let tabBarHeight: CGFloat = 49
    private static let cutoutPadding: CGFloat = 8
    /// 气泡放目标下方还是上方的估算高度：步号行 + 图标与小标题 + 正文四行 + 按钮 + 内边距。
    private static let bubbleEstimatedHeight: CGFloat = 210
    /// 请用户点的那一步外环的最大外扩（呼吸 0 → 7pt）。
    private static let pulseInset: CGFloat = 7

    var body: some View {
        // 中文注释：外层读安全区（它落在安全区内，`safeAreaInsets` 才是真值）；内层忽略安全区铺满整屏画蒙层。
        // 直接在忽略安全区的 reader 里读 `safeAreaInsets` 得到的是 0，「跳过」会压到状态栏、底栏挖空盖不住悬浮底栏。
        GeometryReader { safeProxy in
            let insets: EdgeInsets = safeProxy.safeAreaInsets
            GeometryReader { proxy in
                let cutout: CGRect? = self.cutoutRect(in: proxy, insets: insets)
                ZStack {
                    self.scrim(cutout: cutout, size: proxy.size)

                    if let cutout: CGRect = cutout {
                        self.spotlightRing(cutout: cutout)
                    }

                    switch self.step.mode {
                    case .welcome(let title, let primaryTitle):
                        self.welcomeCard(title: title, primaryTitle: primaryTitle)
                    case .bubble, .tapThrough:
                        self.bubble(cutout: cutout, size: proxy.size, insets: insets)
                    }
                }
                // 中文注释：换步时挖空从上一个矩形动画到下一个；减弱动态效果打开时直接切（第三节）。
                .animation(self.reduceMotion ? nil : .easeInOut(duration: 0.25), value: cutout)
            }
            .ignoresSafeArea()
        }
        .transition(.opacity)
    }

    // MARK: - 蒙层与挖空

    private func cutoutRect(in proxy: GeometryProxy, insets: EdgeInsets) -> CGRect? {
        switch self.step.focus {
        case .none:
            return nil
        case .tabBar:
            // 中文注释：悬浮底栏比 49pt 的条略高一截，再加 8pt 把它整个包住。
            let height: CGFloat = Self.tabBarHeight + insets.bottom + Self.cutoutPadding
            return CGRect(x: 0, y: proxy.size.height - height, width: proxy.size.width, height: height)
        case .anchor(let target, let fallback):
            guard let anchor: Anchor<CGRect> = self.anchors[target] ?? fallback.flatMap({ self.anchors[$0] }) else {
                // 中文注释：目标还没登记（页面还在加载，或 List 里的矩形没传上来）时不挖空，气泡停在屏幕下方（第三节）。
                return nil
            }
            return proxy[anchor].insetBy(dx: -Self.cutoutPadding, dy: -Self.cutoutPadding)
        }
    }

    private func scrim(cutout: CGRect?, size: CGSize) -> some View {
        let shape: SpotlightScrimShape = SpotlightScrimShape(
            cutout: cutout ?? .zero,
            hasCutout: cutout != nil,
            cornerRadius: self.step.cornerRadius
        )
        // 中文注释：只有请用户点的那一步、且目标已登记时，挖空区才放行点击；其余步蒙层整块吞掉。
        let passesThrough: Bool
        if case .tapThrough = self.step.mode, cutout != nil {
            passesThrough = true
        } else {
            passesThrough = false
        }
        let hitShape: SpotlightScrimShape = passesThrough
            ? shape
            : SpotlightScrimShape(cutout: .zero, hasCutout: false, cornerRadius: 0)
        return shape
            .fill(CatalogPalette.tourScrim, style: FillStyle(eoFill: true))
            .contentShape(.interaction, hitShape, eoFill: true)
            .frame(width: size.width, height: size.height)
    }

    /// 外发光的遮罩比挖空大出的边，要盖住模糊晕开的范围。
    private static let glowMargin: CGFloat = 28

    /// 挖空沿边：2pt 多彩渐变描边 + 同渐变经模糊的外发光（亮着的控件像被打光；深色下靠它看出哪块亮着）；
    /// 请用户点的那一步再加一圈青绿细外环呼吸（第八节）。
    /// 中文注释：外发光只向外扩——用「整块减挖空」的形状做遮罩，把晕进挖空内的那一半遮掉，不压到目标里的文字
    /// （2026-10-24 模拟器走查：第 1 步的晕压到空状态说明最后一行，用户要求只向外扩）。
    private func spotlightRing(cutout: CGRect) -> some View {
        let shape: RoundedRectangle = RoundedRectangle(cornerRadius: self.step.cornerRadius, style: .continuous)
        let margin: CGFloat = Self.glowMargin
        return ZStack {
            shape
                .stroke(CatalogPalette.spectrumVividGradient, lineWidth: 10)
                .blur(radius: 7)
                .opacity(CatalogPalette.tourGlowOpacity)
                .mask {
                    SpotlightScrimShape(
                        cutout: CGRect(x: margin, y: margin, width: cutout.width, height: cutout.height),
                        hasCutout: true,
                        cornerRadius: self.step.cornerRadius
                    )
                    .fill(style: FillStyle(eoFill: true))
                    .frame(width: cutout.width + margin * 2, height: cutout.height + margin * 2)
                }
            shape
                .stroke(CatalogPalette.spectrumVividGradient, lineWidth: 2)
            if case .tapThrough = self.step.mode {
                SpotlightPulseRing(
                    cornerRadius: self.step.cornerRadius + Self.pulseInset,
                    maxInset: Self.pulseInset,
                    animates: self.reduceMotion == false
                )
                .id(self.step.id)
            }
        }
        .frame(width: cutout.width, height: cutout.height)
        .position(x: cutout.midX, y: cutout.midY)
        .allowsHitTesting(false)
    }

    // MARK: - 气泡

    private func bubble(cutout: CGRect?, size: CGSize, insets: EdgeInsets) -> some View {
        let bottomLimit: CGFloat = size.height - insets.bottom - 16
        let placeBelow: Bool = cutout.map { rect in
            return rect.maxY + 12 + Self.bubbleEstimatedHeight <= bottomLimit
        } ?? false
        // 中文注释：指针对准目标中点，但不出气泡两端的圆角。
        let maxArrowOffset: CGFloat = max(0, size.width / 2 - 20 - 28)
        let arrowOffset: CGFloat = min(maxArrowOffset, max(-maxArrowOffset, (cutout?.midX ?? size.width / 2) - size.width / 2))
        let topInset: CGFloat = placeBelow ? (cutout?.maxY ?? 0) + 4 : 0
        let bottomInset: CGFloat
        if placeBelow {
            bottomInset = 0
        } else if let cutout: CGRect = cutout {
            bottomInset = size.height - cutout.minY + 4
        } else {
            bottomInset = insets.bottom + 24
        }

        return VStack(spacing: 0) {
            if placeBelow {
                SpotlightArrowShape(pointsUp: true)
                    .fill(CatalogPalette.cardBackground)
                    .frame(width: 16, height: 8)
                    .offset(x: arrowOffset)
            }
            self.bubbleCard
            if placeBelow == false && cutout != nil {
                SpotlightArrowShape(pointsUp: false)
                    .fill(CatalogPalette.cardBackground)
                    .frame(width: 16, height: 8)
                    .offset(x: arrowOffset)
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: placeBelow ? .top : .bottom)
        .padding(.top, topInset)
        .padding(.bottom, bottomInset)
    }

    private var bubbleCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 中文注释：「跳过」放在气泡的步号行右侧，不浮在蒙层右上——那里会压在标题行的计数或按钮上。
            // 库页那一步没有步号，也不需要「跳过」（「知道了」就是关闭）。
            if let counter: String = self.step.counter {
                HStack(alignment: .center, spacing: 6) {
                    if let progress: SpotlightTourProgress = self.step.progress {
                        self.progressSegments(progress)
                    }
                    Text(counter)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button(action: self.skipAction) {
                        Text(self.skipTitle)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 44, minHeight: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(height: 20)
            }

            HStack(alignment: .top, spacing: 12) {
                if let icon: SpotlightTourIcon = self.step.icon {
                    self.iconChip(icon)
                }
                VStack(alignment: .leading, spacing: 4) {
                    if let heading: String = self.step.heading {
                        Text(heading)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(self.step.message)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            switch self.step.mode {
            case .bubble(let buttonTitle):
                Button(action: self.primaryAction) {
                    HStack(spacing: 8) {
                        Text(buttonTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(CatalogPalette.tourOnButton)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(CatalogPalette.tourAccent)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(CatalogPalette.tourButtonFill, in: Capsule(style: .continuous))
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            case .tapThrough(let hint):
                HStack(spacing: 8) {
                    Text(hint)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(CatalogPalette.spectrumVividGradient)
                    Image(systemName: "arrow.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CatalogPalette.tourAccent)
                }
                .frame(height: 32)
                .padding(.horizontal, 2)
            case .welcome:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(CatalogPalette.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        // 中文注释：深色下气泡与蒙层都近黑，加 1pt 白 16% 描边分出边界；浅色不画。
        .overlay {
            if self.colorScheme == .dark {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(CatalogPalette.onDarkFill, lineWidth: 1)
            }
        }
        .shadow(color: CatalogPalette.tourBubbleShadow, radius: 22, y: 10)
    }

    /// 三段 26 × 5 进度条：已到段多彩渐变，未到段次级填充。
    private func progressSegments(_ progress: SpotlightTourProgress) -> some View {
        HStack(spacing: 5) {
            ForEach(1...max(1, progress.total), id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index <= progress.index ? AnyShapeStyle(CatalogPalette.spectrumVividGradient) : AnyShapeStyle(CatalogPalette.fillBackground))
                    .frame(width: 26, height: 5)
            }
        }
        .padding(.trailing, 6)
        .accessibilityHidden(true)
    }

    /// 40pt 墨青圆 + 青绿符号 + 3pt 青绿 22% 光环。
    private func iconChip(_ icon: SpotlightTourIcon) -> some View {
        ZStack {
            Circle()
                .fill(CatalogPalette.brandWaitingFill)
            Image(systemName: icon.systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(CatalogPalette.tourAccent)
        }
        .frame(width: 40, height: 40)
        .overlay {
            Circle()
                .strokeBorder(CatalogPalette.tourAccent.opacity(0.22), lineWidth: 3)
                .padding(-3)
        }
        .accessibilityHidden(true)
    }

    // MARK: - 欢迎卡

    private func welcomeCard(title: String, primaryTitle: String) -> some View {
        VStack(spacing: 0) {
            self.welcomeHero
            VStack(spacing: 12) {
                Text(title)
                    .font(.title2.weight(.heavy))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(self.step.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                self.kindChips
                    .padding(.top, 2)
                Button(action: self.primaryAction) {
                    HStack(spacing: 8) {
                        Text(primaryTitle)
                            .font(.headline)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundStyle(CatalogPalette.onAction)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(CatalogPalette.spectrumVividGradient, in: Capsule(style: .continuous))
                    .contentShape(Capsule(style: .continuous))
                    .shadow(color: CatalogPalette.tourPrimaryShadow, radius: 13, y: 10)
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
                Button(action: self.skipAction) {
                    Text(self.skipTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(EdgeInsets(top: 22, leading: 24, bottom: 20, trailing: 24))
        }
        .background(CatalogPalette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: CatalogPalette.tourBubbleShadow, radius: 30, y: 12)
        .padding(.horizontal, 24)
    }

    /// 上半段 208pt 墨青色块：右上青绿光圈、左下紫光圈、居中 136pt 海报帧圆 + 青绿光环、底部「ANYPORTAL」。
    /// 中文注释：色块深浅同值——浅色页面上它就是一块深色色块，与类型瓷砖同一种语言（第八节）。
    private var welcomeHero: some View {
        ZStack {
            CatalogPalette.brandWaitingFill
            GeometryReader { proxy in
                Circle()
                    .fill(RadialGradient(
                        colors: [CatalogPalette.tourAccent.opacity(0.34), CatalogPalette.tourAccent.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 120
                    ))
                    .frame(width: 240, height: 240)
                    .position(x: proxy.size.width + 50 - 120, y: -70 + 120)
                Circle()
                    .fill(RadialGradient(
                        colors: [CatalogPalette.spectrumVividColors[1].opacity(0.30), CatalogPalette.spectrumVividColors[1].opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 110
                    ))
                    .frame(width: 220, height: 220)
                    .position(x: -60 + 110, y: proxy.size.height + 90 - 110)
            }
            VStack(spacing: 0) {
                // 中文注释：品牌图用等待标记的海报帧，不另出图（第八节）。
                Image("BrandWaitingPoster")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 136, height: 136)
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(CatalogPalette.tourAccent.opacity(0.35), lineWidth: 3)
                            .padding(-3)
                    }
                    .shadow(color: CatalogPalette.tourAccent.opacity(0.35), radius: 20)
                    .padding(.top, 32)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                // 中文注释：品牌名不翻译（裁定 6）。
                Text(verbatim: "ANYPORTAL")
                    .font(.caption2.weight(.semibold))
                    .tracking(3)
                    .foregroundStyle(CatalogPalette.immersiveSecondaryText)
                    .padding(.bottom, 14)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: 208)
        .clipped()
    }

    /// 三枚类型胶囊：类型色字 + 12% 底 + 20pt 同色圆白图标（裁定 2）。
    private var kindChips: some View {
        HStack(spacing: 8) {
            ForEach([CatalogSourceKind.video, .comic, .book], id: \.self) { kind in
                let style: CatalogKindStyle = CatalogKindStyle.of(kind)
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(style.accent)
                        Image(systemName: style.symbolName)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(CatalogPalette.onAccent)
                    }
                    .frame(width: 20, height: 20)
                    Text(style.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(style.accent)
                        .lineLimit(1)
                }
                .padding(.leading, 6)
                .padding(.trailing, 12)
                .frame(height: 30)
                .background(style.accent.opacity(0.12), in: Capsule(style: .continuous))
            }
        }
    }

}

/// 整屏矩形减去一个圆角矩形（even-odd），既是蒙层的形状也是它的命中区域。
private struct SpotlightScrimShape: Shape {
    var cutout: CGRect
    var hasCutout: Bool
    var cornerRadius: CGFloat

    var animatableData: AnimatablePair<CGRect.AnimatableData, CGFloat> {
        get {
            return AnimatablePair(self.cutout.animatableData, self.cornerRadius)
        }
        set {
            self.cutout.animatableData = newValue.first
            self.cornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path: Path = Path(rect)
        if self.hasCutout {
            path.addRoundedRect(
                in: self.cutout,
                cornerSize: CGSize(width: self.cornerRadius, height: self.cornerRadius),
                style: .continuous
            )
        }
        return path
    }
}

/// 请用户点的那一步：挖空外 1.5pt 青绿 45% 外环，外扩 0 → 7pt 来回，1.6 秒一次；减弱动态效果打开时停在最外圈。
private struct SpotlightPulseRing: View {
    let cornerRadius: CGFloat
    let maxInset: CGFloat
    let animates: Bool

    @State private var expanded: Bool = false

    var body: some View {
        let inset: CGFloat = self.expanded || self.animates == false ? self.maxInset : 0
        RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
            .strokeBorder(CatalogPalette.tourAccent.opacity(0.45), lineWidth: 1.5)
            .padding(-inset)
            .onAppear {
                guard self.animates else {
                    return
                }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    self.expanded = true
                }
            }
            .accessibilityHidden(true)
    }
}

/// 气泡的三角指针。
private struct SpotlightArrowShape: Shape {
    let pointsUp: Bool

    func path(in rect: CGRect) -> Path {
        var path: Path = Path()
        if self.pointsUp {
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}
