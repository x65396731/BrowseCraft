import Foundation
import Observation

// 中文注释：OnboardingTour.swift 属于界面功能层，承载新手引导的判定、阶段机与各步文案
// （`docs/design/Onboarding-Design.md`）。引导层本身在 `SpotlightTourOverlay`，根视图把这里的当前步交给它画。
// 2026-10-24 v2：每步多一行小标题与一枚图标（第四节，用户裁定 1 取 A）；第 1、3 步的小标题随回看形态换备选。

/// 新手引导的呈现判定与版本号。
enum OnboardingGuide {
    /// 来源页部分看过的版本号存这里（关闭即记，不论从哪一步离开）。
    static let seenVersionKey: String = "onboardingSeenVersion"
    /// 库页那一步看过的标记。
    static let libraryHintSeenKey: String = "onboardingLibraryHintSeen"
    /// 文案实质改版时 +1 让老用户再看一次；只改错别字不动。
    static let currentVersion: Int = 1
    #if DEBUG
    /// 仅 DEBUG——演示模式种了来源，模拟器里不加这个参数看不到引导；截图也从这里出。
    static let forceLaunchArgument: String = "-BrowseCraftShowOnboarding"
    #endif

    /// 中文注释：本机没有来源且没看过当前版本才弹；已有来源的用户无论版本号都不弹（会添加来源就已经会用了）。
    static func shouldPresent(seenVersion: Int, hasSources: Bool) -> Bool {
        if hasSources {
            return false
        }
        return seenVersion < Self.currentVersion
    }
}

/// 来源页上被点的入口：第 3 步的两个出口。
enum OnboardingSourcesEntry {
    case catalog
    case generate
}

/// 引导的阶段：来源页四步（欢迎卡 + 三步）与库页一步。
enum OnboardingPhase: Equatable {
    case idle
    case welcome
    case sourcesStep1
    case sourcesStep2
    case sourcesStep3
    /// 等库页登记第一张封面；用户离开库标签即作废。
    case libraryHintPending
    case libraryHint
}

/// 阶段机、两个已看标记与埋点。由根视图持有，经环境给来源页告知入口被点。
@MainActor
@Observable
final class OnboardingTourStore {
    private(set) var phase: OnboardingPhase = .idle
    private(set) var entry: OnboardingEntry = .firstRun
    /// 中文注释：第 3 步点「用网址生成」走出去时置位，合格入口页引导屏读到它才显示眉行「新手引导 · 最后一步」，
    /// 引导屏点按钮或关掉时清掉（第五节；Generation-Input-Page-Redesign-Design.md 第三节「引导屏」）。
    private(set) var cameFromTour: Bool = false
    @ObservationIgnored
    private let defaults: UserDefaults
    @ObservationIgnored
    private let isForced: Bool

    init(defaults: UserDefaults = .standard, arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.defaults = defaults
        #if DEBUG
        self.isForced = arguments.contains(OnboardingGuide.forceLaunchArgument)
        #else
        self.isForced = false
        #endif
    }

    var isActive: Bool {
        return self.phase != .idle
    }

    // MARK: - 起止

    /// 开屏结束落到来源页时调用；该弹就起欢迎卡。
    func startFirstRunIfNeeded(hasSources: Bool) {
        guard self.phase == .idle else {
            return
        }
        let seenVersion: Int = self.defaults.integer(forKey: OnboardingGuide.seenVersionKey)
        guard self.isForced || OnboardingGuide.shouldPresent(seenVersion: seenVersion, hasSources: hasSources) else {
            return
        }
        self.entry = .firstRun
        self.phase = .welcome
    }

    /// 设置页「关于」组回看：重放欢迎卡与三步，库页那一步在下次进库时再给一次（第六节）。
    func replay() {
        self.entry = .help
        self.defaults.set(false, forKey: OnboardingGuide.libraryHintSeenKey)
        self.phase = .welcome
    }

    /// 欢迎卡「开始」、气泡「下一步」「知道了」。
    func advance() {
        switch self.phase {
        case .welcome:
            self.phase = .sourcesStep1
        case .sourcesStep1:
            self.phase = .sourcesStep2
        case .sourcesStep2:
            self.phase = .sourcesStep3
        case .libraryHint:
            self.finishLibraryHint()
        case .idle, .sourcesStep3, .libraryHintPending:
            break
        }
    }

    /// 右上「跳过」与欢迎卡的「跳过」：记为看过，库页那一步也不再给（第五节）。
    func skip() {
        switch self.phase {
        case .welcome:
            self.finishSourcesTour(.skippedWelcome, givesLibraryHint: false)
        case .sourcesStep1:
            self.finishSourcesTour(.skipped1, givesLibraryHint: false)
        case .sourcesStep2:
            self.finishSourcesTour(.skipped2, givesLibraryHint: false)
        case .sourcesStep3:
            self.finishSourcesTour(.skipped3, givesLibraryHint: false)
        case .libraryHint:
            self.finishLibraryHint()
        case .idle, .libraryHintPending:
            break
        }
    }

    /// 来源页入口卡或右上胶囊被点：第 3 步的出口；其他阶段不理会。
    func noteSourcesEntryTapped(_ entry: OnboardingSourcesEntry) {
        guard self.phase == .sourcesStep3 else {
            return
        }
        switch entry {
        case .catalog:
            self.finishSourcesTour(.catalog, givesLibraryHint: true)
        case .generate:
            self.cameFromTour = true
            self.finishSourcesTour(.generate, givesLibraryHint: true)
        }
    }

    /// 引导屏看过眉行了（点了按钮或关掉）：下次从输入页回看、或下次再添加来源都不再显示。
    func clearCameFromTour() {
        self.cameFromTour = false
    }

    /// 切到库标签（含添加来源后自动切过去）时调用：没看过库页那一步就等它登记第一张封面。
    func requestLibraryHint() {
        guard self.phase == .idle else {
            return
        }
        guard self.isForced || self.defaults.bool(forKey: OnboardingGuide.libraryHintSeenKey) == false else {
            return
        }
        self.phase = .libraryHintPending
    }

    /// 等待期间离开了库标签：这一步作废（第五节）。
    func cancelPendingLibraryHint() {
        if self.phase == .libraryHintPending {
            self.phase = .idle
        }
    }

    /// 根视图看到第一张封面登记上来了。
    func showLibraryHintIfPending() {
        if self.phase == .libraryHintPending {
            self.phase = .libraryHint
        }
    }

    private func finishSourcesTour(_ result: OnboardingResult, givesLibraryHint: Bool) {
        self.defaults.set(OnboardingGuide.currentVersion, forKey: OnboardingGuide.seenVersionKey)
        if givesLibraryHint == false {
            self.defaults.set(true, forKey: OnboardingGuide.libraryHintSeenKey)
        }
        AppAnalytics.shared.logOnboardingFinished(entry: self.entry, result: result)
        self.phase = .idle
    }

    private func finishLibraryHint() {
        guard self.phase == .libraryHint else {
            return
        }
        self.defaults.set(true, forKey: OnboardingGuide.libraryHintSeenKey)
        AppAnalytics.shared.logOnboardingFinished(entry: self.entry, result: .libraryDone)
        self.phase = .idle
    }

    // MARK: - 当前步

    /// 当前步的目标与文案（第四节）；`hasSources` 决定回看时用备选目标与备选文案。
    func currentStep(hasSources: Bool) -> SpotlightTourStep? {
        let totalSteps: Int = 3
        switch self.phase {
        case .idle, .libraryHintPending:
            return nil
        case .welcome:
            return SpotlightTourStep(
                id: "welcome",
                focus: .none,
                progress: nil,
                counter: nil,
                heading: nil,
                icon: nil,
                message: NSLocalizedString("onboarding_welcome_message", comment: "欢迎卡正文"),
                mode: .welcome(
                    title: NSLocalizedString("onboarding_welcome_title", comment: "欢迎卡标题"),
                    primaryTitle: NSLocalizedString("onboarding_start", comment: "欢迎卡「开始」")
                ),
                cornerRadius: 0
            )
        case .sourcesStep1:
            return SpotlightTourStep(
                id: "sources-1",
                focus: .anchor(.sourcesEmptyState, fallback: .sourcesInUseCard),
                progress: SpotlightTourProgress(index: 1, total: totalSteps),
                counter: Self.counter(1, of: totalSteps),
                heading: NSLocalizedString(
                    hasSources ? "onboarding_heading_sources_in_use" : "onboarding_heading_sources_empty",
                    comment: "第 1 步小标题"
                ),
                icon: .globe,
                message: NSLocalizedString(
                    hasSources ? "onboarding_step_sources_in_use" : "onboarding_step_sources_empty",
                    comment: "第 1 步正文"
                ),
                mode: .bubble(buttonTitle: NSLocalizedString("onboarding_next", comment: "下一步")),
                // 中文注释：空状态块圆角按 18 算，「正在使用」卡 24；挖空圆角 = 目标圆角 + 4（第八节）。
                cornerRadius: hasSources ? 28 : 22
            )
        case .sourcesStep2:
            return SpotlightTourStep(
                id: "sources-2",
                focus: .tabBar,
                progress: SpotlightTourProgress(index: 2, total: totalSteps),
                counter: Self.counter(2, of: totalSteps),
                heading: NSLocalizedString("onboarding_heading_tabs", comment: "第 2 步小标题"),
                icon: .tabs,
                message: NSLocalizedString("onboarding_step_tabs", comment: "第 2 步正文"),
                mode: .bubble(buttonTitle: NSLocalizedString("onboarding_next", comment: "下一步")),
                cornerRadius: 12
            )
        case .sourcesStep3:
            return SpotlightTourStep(
                id: "sources-3",
                focus: .anchor(.sourcesEntryCards, fallback: .sourcesActionCapsule),
                progress: SpotlightTourProgress(index: 3, total: totalSteps),
                counter: Self.counter(3, of: totalSteps),
                heading: NSLocalizedString(
                    hasSources ? "onboarding_heading_entry_capsule" : "onboarding_heading_entry_cards",
                    comment: "第 3 步小标题"
                ),
                icon: .plus,
                message: NSLocalizedString(
                    hasSources ? "onboarding_step_entry_capsule" : "onboarding_step_entry_cards",
                    comment: "第 3 步正文"
                ),
                mode: .tapThrough(
                    hint: NSLocalizedString(
                        hasSources ? "onboarding_step_entry_capsule_hint" : "onboarding_step_entry_hint",
                        comment: "第 3 步提示句"
                    )
                ),
                // 中文注释：入口卡圆角 18；右上胶囊高 44、圆角 22。
                cornerRadius: hasSources ? 26 : 22
            )
        case .libraryHint:
            return SpotlightTourStep(
                id: "library",
                focus: .anchor(.libraryFirstCover, fallback: nil),
                progress: nil,
                counter: nil,
                heading: NSLocalizedString("onboarding_heading_library", comment: "库页那一步小标题"),
                icon: .heart,
                message: NSLocalizedString("onboarding_library_hint", comment: "库页那一步正文"),
                mode: .bubble(buttonTitle: NSLocalizedString("onboarding_done", comment: "知道了")),
                // 中文注释：海报圆角 14。
                cornerRadius: 18
            )
        }
    }

    private static func counter(_ index: Int, of total: Int) -> String {
        return String(
            format: NSLocalizedString("onboarding_step_counter", comment: "步号「1 / 3」"),
            index,
            total
        )
    }
}
