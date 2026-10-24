import BrowseCraftDomain
import Foundation
import SwiftUI

// 中文注释：`BC-PAGE-060` 定义的合格入口页两要素——①要有分页 ②必须是单 list family——
// 在 App 里此前一个字都没有：输入框只写「List 或分类页面 URL」，footer 写的是免责声明。
// 要素一预检根本不判（`AssessVideoGenerationInputUseCase` 只 observe + assess family），
// 用户要等服务端拒了才知道（2026-09-20 真机 gimy `/browse/3.html` 就是白等一次生成）。
// 条款自己留了这个位置：「不满足就拒绝并说明原因，由用户改用合格的入口地址
// （教程属产品侧，不在引擎内解决）」——这一屏就是那份教程。
//
// 它**不判定任何东西**：零网络、零登录、不改 `VideoGenerationInputPreflight.schemaVersion`。
// 服务端已有的同源判定端点（`POST /v1/rule-generations/entry-page-qualification`）
// 用户 2026-09-20 裁定不接线，本屏不改变那个决定。
//
// 2026-10-24 v2（Generation-Input-Page-Redesign-Design.md 第三节「引导屏」，用户六项裁定全取 A）：它是走生成这条路的
// 新用户必经的一屏，按新手引导 v2 同一块语言重画（墨青色块上半段、三组卡片、主按钮固定底部），从新手引导第 3 步
// 走来的那一次顶部多一行眉行；位置、文案、版本号与「首次必过」的判定不动。

enum EntryPageGuide {
    /// 中文注释：读过的版本号存这里。文案实质改版时把 `currentVersion` +1，老用户再看一次；
    /// 只改错别字不要动它，否则每个人都被多拦一屏。
    static let seenVersionKey: String = "entryPageGuideSeenVersion"
    /// 版本 2（2026-09-23，`BC-PAGE-061`）：分页说明改成「点到第 2 页地址会变」，并加一行「满足两条也可能生成不了」。
    /// 版本 3（2026-09-23）：首页入口不再支持；例子改成「全部」类列表页，其余内容靠搜索找到。
    /// 版本 4（2026-09-29，`BC-PAGE-063` ⑥）：版本 3 教的「全部」页每排筛选都打头，引擎不推导分类；
    /// 改成只在一排筛选里选一个不是「全部」的选项，这一排连同「全部」一起生成为分类。
    static let currentVersion: Int = 4

    /// 中文注释：判定单独拿出来是为了可测——视图里的那份是 `private` 计算属性，测不到。
    /// 本次已经点过「我找到了这样的页面」就不再拦（`didAcknowledge`），
    /// 否则看存过的版本号：没看过、或看的是更早一版，都要再看一次。
    static func shouldPresent(seenVersion: Int, didAcknowledge: Bool) -> Bool {
        if didAcknowledge {
            return false
        }
        return seenVersion < Self.currentVersion
    }
}

/// 合格入口页引导屏。两种用法由 `primaryTitleKey` 与 `cancelAction` 区分：
/// 首屏（必过一次，带「取消」关掉整个流程）与回看（从输入页或失败行叠一层 sheet，只有「知道了」）。
struct EntryPageGuideView: View {
    /// 中文注释：失败行拉起这一屏时拿不到 kind——`/outcomes` 每条只有 jobId / entryURL /
    /// status / finishedAt / reason(Detail) / catalogSourceId（`BC-PREFLIGHT-056` 定死的字段），
    /// 没有 `sourceKind`。那种情况传 nil，举例退回 kind 中性的一句，不猜。
    let sourceKind: RuleGenerationSourceKind?
    let primaryTitleKey: String
    let primaryAction: () -> Void
    /// 中文注释：只有首屏形态有取消——回看形态是叠在别人上面的 sheet，关掉它用 `primaryAction` 就够。
    let cancelAction: (() -> Void)?
    /// 中文注释：`generation_guide_finished` 的入口：首次必过的那屏传 `.firstRun`，其余回看入口用缺省的 `.help`。
    var analyticsEntry: GenerationGuideEntry = .help
    /// 中文注释：从新手引导第 3 步走来的那一次才显示眉行「新手引导 · 最后一步」；回看形态永远没有。
    var showsTourEyebrow: Bool = false

    /// 中文注释：本次显示是否已经报过结局；点按钮报过后，随之而来的 `onDisappear` 不再按「下滑关掉」补报取消。
    @State private var hasReportedFinish: Bool = false

    @Environment(\.colorScheme) private var colorScheme: ColorScheme

    /// 首屏形态（带「取消」）：主按钮多彩渐变；回看形态：墨青实心。
    private var isFirstRunForm: Bool {
        return self.cancelAction != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                self.hero
                self.illustrationCard
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                self.sectionTitle("entry_guide_requirements_title")
                    .padding(.top, 22)
                self.card {
                    self.requirementRow(
                        systemImage: "list.number",
                        titleKey: "entry_guide_rule_pagination_title",
                        detailKey: "entry_guide_rule_pagination_detail"
                    )
                    SettingsRowSeparator(leadingInset: 68)
                    self.requirementRow(
                        systemImage: "square.grid.2x2",
                        titleKey: "entry_guide_rule_single_list_title",
                        detailKey: "entry_guide_rule_single_list_detail"
                    )
                }
                // 中文注释：`BC-PAGE-061` 全站直出拦的是作品页 / 阅读页里的额外接口与解密，
                // 用户在列表页上看不出来——先说一句，免得照着两条做了却被拒时觉得被骗。
                Text(NSLocalizedString("entry_guide_requirements_caveat", comment: ""))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                self.sectionTitle("entry_guide_examples_title")
                    .padding(.top, 22)
                self.card {
                    self.exampleRow(
                        systemImage: "xmark",
                        tint: CatalogPalette.warning,
                        fill: CatalogPalette.warningFill,
                        textKey: "entry_guide_example_bad"
                    )
                    SettingsRowSeparator(leadingInset: 68)
                    self.exampleRow(
                        systemImage: "checkmark",
                        tint: CatalogKindStyle.of(CatalogSourceKind.book).accent,
                        fill: CatalogPalette.tourAccent.opacity(0.16),
                        textKey: self.goodExampleKey
                    )
                }

                self.sectionTitle("entry_guide_steps_title")
                    .padding(.top, 22)
                self.card {
                    ForEach(Array(Self.stepKeys.enumerated()), id: \.offset) { index, key in
                        if index > 0 {
                            SettingsRowSeparator(leadingInset: 54)
                        }
                        self.stepRow(number: index + 1, textKey: key)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .background(CatalogPalette.pageBackground)
        // 中文注释：主按钮固定在底部（裁定 4），内容在它下面滚；底栏页底色 90% + 毛玻璃。
        .safeAreaInset(edge: .bottom, spacing: 0) {
            self.primaryButton
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 12)
                .background {
                    CatalogPalette.pageBackground.opacity(0.9)
                        .background(.ultraThinMaterial)
                        .ignoresSafeArea(edges: .bottom)
                }
        }
        // 中文注释：整页自绘，系统导航栏藏起来；「取消」画在上半段色块里。
        .toolbar(.hidden, for: .navigationBar)
        .analyticsScreen(.entryGuide)
        .onAppear {
            self.hasReportedFinish = false
        }
        .onDisappear {
            // 中文注释：没点任何按钮就消失的是下滑关掉 sheet，算取消。
            self.reportFinish(.cancelled)
        }
    }

    private func reportFinish(_ result: GenerationGuideResult) {
        guard self.hasReportedFinish == false else {
            return
        }
        self.hasReportedFinish = true
        AppAnalytics.shared.logGenerationGuideFinished(entry: self.analyticsEntry, result: result)
    }

    private static let stepKeys: [String] = [
        "entry_guide_step_1",
        "entry_guide_step_2",
        "entry_guide_step_3"
    ]

    /// 中文注释：两条要素是 kind 中性的（`list_stage_flow` 三种 kind 共用同一道判据），
    /// 按 kind 变的只有这一句举例——视频/漫画说分类页，书说排行榜页。
    private var goodExampleKey: String {
        switch self.sourceKind {
        case .video:
            return "entry_guide_example_good_video"
        case .comic:
            return "entry_guide_example_good_comic"
        case .book:
            return "entry_guide_example_good_book"
        case nil:
            return "entry_guide_example_good_generic"
        }
    }

    // MARK: - 上半段墨青色块

    /// 墨青色块：右上青绿光圈、首屏形态的「取消」、眉行、大标题、一句说明。
    /// 中文注释：色块深浅同值，浅色页面上就是一块深色色块，与欢迎卡上半段同一种语言。
    private var hero: some View {
        ZStack(alignment: .topLeading) {
            CatalogPalette.brandWaitingFill
            GeometryReader { proxy in
                Circle()
                    .fill(RadialGradient(
                        colors: [CatalogPalette.tourAccent.opacity(0.32), CatalogPalette.tourAccent.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 130
                    ))
                    .frame(width: 260, height: 260)
                    .position(x: proxy.size.width + 70 - 130, y: -90 + 130)
            }
            VStack(alignment: .leading, spacing: 8) {
                if let cancelAction: () -> Void = self.cancelAction {
                    Button {
                        self.reportFinish(.cancelled)
                        cancelAction()
                    } label: {
                        Text(NSLocalizedString("Cancel", comment: ""))
                            .font(.body)
                            .foregroundStyle(CatalogPalette.immersiveText.opacity(0.82))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    // 中文注释：回看形态没有取消，留出与首屏相近的顶部空白，标题不贴 sheet 顶边。
                    Color.clear
                        .frame(height: 36)
                }
                if self.showsTourEyebrow {
                    HStack(spacing: 6) {
                        Image(systemName: "triangle.fill")
                            .font(.system(size: 9, weight: .bold))
                            .rotationEffect(.degrees(180))
                        Text(NSLocalizedString("entry_guide_tour_eyebrow", comment: "引导屏眉行：从新手引导走来"))
                            .font(.caption2.weight(.bold))
                            .tracking(1)
                    }
                    .foregroundStyle(CatalogPalette.tourAccent)
                    .padding(.top, 4)
                }
                Text(NSLocalizedString("entry_guide_title", comment: ""))
                    .font(.title.weight(.heavy))
                    .foregroundStyle(CatalogPalette.immersiveText)
                    .accessibilityAddTraits(.isHeader)
                Text(NSLocalizedString("entry_guide_subtitle", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(CatalogPalette.immersiveEyebrow)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(EdgeInsets(top: 12, leading: 24, bottom: 24, trailing: 24))
        }
        .clipped()
    }

    /// 反例插画卡：她指着的那块卡片画的就是反例——几块区块拼起来、底部没有页码。
    /// 中文注释：插画本身白底，卡固定白，深色下白卡就是它的画框（裁定 6）。
    private var illustrationCard: some View {
        Image("EntryGuideUnsupportedPage")
            .resizable()
            .scaledToFit()
            .frame(height: 150)
            .frame(maxWidth: .infinity)
            .frame(height: 176)
            .background(CatalogPalette.tourIllustrationCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .accessibilityHidden(true)
    }

    // MARK: - 三组卡片

    private func sectionTitle(_ key: String) -> some View {
        Text(NSLocalizedString(key, comment: ""))
            .font(.footnote.weight(.bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .background(CatalogPalette.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                if self.colorScheme == .dark {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(CatalogPalette.onDarkFill, lineWidth: 1)
                }
            }
            .padding(.horizontal, 20)
    }

    private func requirementRow(
        systemImage: String,
        titleKey: String,
        detailKey: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            self.inkChip(systemImage: systemImage)
            VStack(alignment: .leading, spacing: 3) {
                Text(NSLocalizedString(titleKey, comment: ""))
                    .font(.subheadline.weight(.semibold))
                Text(NSLocalizedString(detailKey, comment: ""))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func exampleRow(systemImage: String, tint: Color, fill: Color, textKey: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(fill, in: Circle())
                .accessibilityHidden(true)
            Text(NSLocalizedString(textKey, comment: ""))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func stepRow(number: Int, textKey: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: "\(number)")
                .font(.footnote.weight(.heavy))
                .foregroundStyle(CatalogPalette.onAction)
                .frame(width: 26, height: 26)
                .background(CatalogPalette.spectrumVividGradient, in: Circle())
                .accessibilityHidden(true)
            Text(NSLocalizedString(textKey, comment: ""))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    /// 40pt 墨青圆 + 青绿线性符号 + 3pt 青绿 22% 光环，与新手引导气泡的图标同一做法。
    private func inkChip(systemImage: String) -> some View {
        ZStack {
            Circle()
                .fill(CatalogPalette.brandWaitingFill)
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
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

    // MARK: - 主按钮

    @ViewBuilder
    private var primaryButton: some View {
        if self.isFirstRunForm {
            Button {
                self.reportFinish(.continued)
                self.primaryAction()
            } label: {
                HStack(spacing: 8) {
                    Text(NSLocalizedString(self.primaryTitleKey, comment: ""))
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
        } else {
            Button {
                self.reportFinish(.continued)
                self.primaryAction()
            } label: {
                HStack(spacing: 8) {
                    Text(NSLocalizedString(self.primaryTitleKey, comment: ""))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CatalogPalette.tourOnButton)
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CatalogPalette.tourAccent)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(CatalogPalette.tourButtonFill, in: Capsule(style: .continuous))
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

/// 添加来源选完 kind 之后的整条流程：先引导屏（首次必过），再预检输入页。
///
/// 中文注释：**刻意不做 push/pop 两页**，而是条件渲染两个各自带导航栈的分支。
/// 输入页的 `onDisappear` 绑着 `onFinished()`（三种关法一个落点，见 `AddSourceView`），
/// 一旦做成第二页，用户按系统返回键回引导屏就会触发 `onDisappear`，把整个 sheet 关掉。
/// 条件渲染下输入页只在 sheet 真被关闭时 disappear，那条纪律原样成立，
/// `VideoGenerationInputView` 的 body 一行都不用改。
/// 同理，输入页上的「怎样的页面能生成？」是**叠一层 sheet**，不是退回上一页。
struct EntryPageGuideFlowView: View {
    @Bindable var viewModel: SourcesViewModel
    let sourceKind: RuleGenerationSourceKind
    let onFinished: () -> Void

    @AppStorage(EntryPageGuide.seenVersionKey) private var seenVersion: Int = 0
    @State private var didAcknowledge: Bool = false
    /// 中文注释：从新手引导第 3 步走来的那一次，引导屏顶部多一行眉行；看过（点按钮或取消）就清掉。
    @Environment(OnboardingTourStore.self) private var onboardingTour: OnboardingTourStore?

    var body: some View {
        if self.showsGuide {
            NavigationStack {
                EntryPageGuideView(
                    sourceKind: self.sourceKind,
                    primaryTitleKey: "entry_guide_continue_button",
                    primaryAction: self.acknowledge,
                    cancelAction: self.cancel,
                    analyticsEntry: .firstRun,
                    showsTourEyebrow: self.onboardingTour?.cameFromTour == true
                )
            }
        } else {
            // 中文注释：输入页自带 `NavigationStack`，这里不能再包一层，否则两个导航栏叠着出。
            VideoGenerationInputView(
                viewModel: self.viewModel,
                sourceKind: self.sourceKind,
                onFinished: self.onFinished
            )
        }
    }

    private var showsGuide: Bool {
        return EntryPageGuide.shouldPresent(
            seenVersion: self.seenVersion,
            didAcknowledge: self.didAcknowledge
        )
    }

    private func acknowledge() {
        self.onboardingTour?.clearCameFromTour()
        self.seenVersion = EntryPageGuide.currentVersion
        self.didAcknowledge = true
    }

    private func cancel() {
        self.onboardingTour?.clearCameFromTour()
        self.onFinished()
    }
}
