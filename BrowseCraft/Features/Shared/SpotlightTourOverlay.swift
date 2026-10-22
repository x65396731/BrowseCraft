import SwiftUI

// 中文注释：SpotlightTourOverlay.swift 属于界面功能层的共用组件，承载新手引导的「聚光灯气泡层」
// （`docs/design/Onboarding-Design.md` 第三节）。它不持有任何页面逻辑（`BCA-UI-009`）：页面用 `spotlightTarget`
// 登记目标矩形，这一层只按当前步画蒙层、挖空与气泡；请用户点的那一步把挖空区的点击放行，控件的原动作照常执行。

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
    /// 步号「1 / 3」，欢迎卡与库页那一步没有。
    let counter: String?
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

    private static let tabBarHeight: CGFloat = 49
    private static let cutoutPadding: CGFloat = 8
    /// 气泡放目标下方还是上方的估算高度：正文四行 + 按钮 + 内边距。
    private static let bubbleEstimatedHeight: CGFloat = 170

    var body: some View {
        // 中文注释：外层读安全区（它落在安全区内，`safeAreaInsets` 才是真值）；内层忽略安全区铺满整屏画蒙层。
        // 直接在忽略安全区的 reader 里读 `safeAreaInsets` 得到的是 0，「跳过」会压到状态栏、底栏挖空盖不住悬浮底栏。
        GeometryReader { safeProxy in
            let insets: EdgeInsets = safeProxy.safeAreaInsets
            GeometryReader { proxy in
                let cutout: CGRect? = self.cutoutRect(in: proxy, insets: insets)
                ZStack {
                    self.scrim(cutout: cutout, size: proxy.size)

                    // 中文注释：挖空描一圈 1pt 半透明白：深色下蒙层与页面都近黑，没有它看不出哪块是亮着的（第八节）。
                    if let cutout: CGRect = cutout {
                        RoundedRectangle(cornerRadius: self.step.cornerRadius, style: .continuous)
                            .strokeBorder(CatalogPalette.onDarkFill, lineWidth: 1)
                            .frame(width: cutout.width, height: cutout.height)
                            .position(x: cutout.midX, y: cutout.midY)
                            .allowsHitTesting(false)
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

    // MARK: - 气泡

    private func bubble(cutout: CGRect?, size: CGSize, insets: EdgeInsets) -> some View {
        let bottomLimit: CGFloat = size.height - insets.bottom - 16
        let placeBelow: Bool = cutout.map { rect in
            return rect.maxY + 12 + Self.bubbleEstimatedHeight <= bottomLimit
        } ?? false
        // 中文注释：指针对准目标中点，但不出气泡两端的圆角。
        let maxArrowOffset: CGFloat = max(0, size.width / 2 - 24 - 24)
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
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: placeBelow ? .top : .bottom)
        .padding(.top, topInset)
        .padding(.bottom, bottomInset)
    }

    private var bubbleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 中文注释：「跳过」放在气泡的步号行右侧，不再浮在蒙层右上——那里会压在标题行的计数或按钮上。
            // 库页那一步没有步号，也不需要「跳过」（「知道了」就是关闭）。
            if let counter: String = self.step.counter {
                HStack(alignment: .center) {
                    Text(counter)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button(action: self.skipAction) {
                        Text(self.skipTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CatalogPalette.settingsIcon)
                            .frame(minWidth: 44, minHeight: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(height: 20)
            }
            Text(self.step.message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            switch self.step.mode {
            case .bubble(let buttonTitle):
                Button(action: self.primaryAction) {
                    Text(buttonTitle)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(CatalogPalette.addAction)
                .foregroundStyle(CatalogPalette.onAction)
            case .tapThrough(let hint):
                Text(hint)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(CatalogPalette.settingsIcon)
            case .welcome:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(CatalogPalette.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 欢迎卡

    private func welcomeCard(title: String, primaryTitle: String) -> some View {
        VStack(spacing: 12) {
            // 中文注释：品牌图用等待标记的海报帧，不另出图（第八节）。
            Image("BrandWaitingPoster")
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(Circle())
                .accessibilityHidden(true)
                .padding(.bottom, 4)
            Text(title)
                .font(.title2.weight(.heavy))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(self.step.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: self.primaryAction) {
                Text(primaryTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(CatalogPalette.addAction)
            .foregroundStyle(CatalogPalette.onAction)
            .padding(.top, 8)
            Button(action: self.skipAction) {
                Text(self.skipTitle)
                    .font(.subheadline)
                    .frame(minHeight: 44)
            }
            .foregroundStyle(CatalogPalette.settingsIcon)
        }
        .padding(24)
        .background(CatalogPalette.cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 28)
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
