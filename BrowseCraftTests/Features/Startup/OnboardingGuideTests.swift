import Foundation
import Testing
@testable import BrowseCraft

/// 新手引导（`docs/design/Onboarding-Design.md`）：呈现判定、阶段机的起止与两个已看标记。
@MainActor
struct OnboardingGuideTests {
    @Test("本机没有来源且没看过时呈现")
    func presentsWhenNoSourcesAndNeverSeen() {
        #expect(OnboardingGuide.shouldPresent(seenVersion: 0, hasSources: false) == true)
    }

    @Test("已有来源的用户无论版本号都不呈现")
    func skipsWhenSourcesExist() {
        #expect(OnboardingGuide.shouldPresent(seenVersion: 0, hasSources: true) == false)
    }

    @Test("看过当前版本后不再呈现，版本号加一后再看一次")
    func respectsSeenVersion() {
        #expect(OnboardingGuide.shouldPresent(seenVersion: OnboardingGuide.currentVersion, hasSources: false) == false)
        #expect(OnboardingGuide.shouldPresent(seenVersion: OnboardingGuide.currentVersion - 1, hasSources: false) == true)
    }

    @Test("第 3 步点入口卡结束：记为看过，库页那一步仍会给")
    func entryTapFinishesSourcesTourAndKeepsLibraryHint() {
        let defaults: UserDefaults = Self.makeDefaults()
        let store: OnboardingTourStore = OnboardingTourStore(defaults: defaults, arguments: [])
        store.startFirstRunIfNeeded(hasSources: false)
        #expect(store.phase == .welcome)
        store.advance()
        store.advance()
        store.advance()
        #expect(store.phase == .sourcesStep3)
        // 中文注释：第 3 步没有「下一步」，再 advance 不动。
        store.advance()
        #expect(store.phase == .sourcesStep3)
        store.noteSourcesEntryTapped(.catalog)
        #expect(store.phase == .idle)
        #expect(defaults.integer(forKey: OnboardingGuide.seenVersionKey) == OnboardingGuide.currentVersion)
        store.requestLibraryHint()
        #expect(store.phase == .libraryHintPending)
        store.showLibraryHintIfPending()
        #expect(store.phase == .libraryHint)
        store.advance()
        #expect(store.phase == .idle)
        #expect(defaults.bool(forKey: OnboardingGuide.libraryHintSeenKey) == true)
    }

    @Test("跳过：记为看过，库页那一步也不再给")
    func skipMarksBothSeen() {
        let defaults: UserDefaults = Self.makeDefaults()
        let store: OnboardingTourStore = OnboardingTourStore(defaults: defaults, arguments: [])
        store.startFirstRunIfNeeded(hasSources: false)
        store.advance()
        store.skip()
        #expect(store.phase == .idle)
        #expect(defaults.integer(forKey: OnboardingGuide.seenVersionKey) == OnboardingGuide.currentVersion)
        store.requestLibraryHint()
        #expect(store.phase == .idle)
        store.startFirstRunIfNeeded(hasSources: false)
        #expect(store.phase == .idle)
    }

    @Test("离开库标签作废等待中的库页那一步；回看重放并把库页那一步放回")
    func pendingHintCancelsAndReplayRestores() {
        let defaults: UserDefaults = Self.makeDefaults()
        defaults.set(OnboardingGuide.currentVersion, forKey: OnboardingGuide.seenVersionKey)
        defaults.set(true, forKey: OnboardingGuide.libraryHintSeenKey)
        let store: OnboardingTourStore = OnboardingTourStore(defaults: defaults, arguments: [])
        store.requestLibraryHint()
        #expect(store.phase == .idle)
        store.replay()
        #expect(store.phase == .welcome)
        #expect(store.entry == .help)
        store.skip()
        store.requestLibraryHint()
        #expect(store.phase == .idle)
        defaults.set(false, forKey: OnboardingGuide.libraryHintSeenKey)
        store.requestLibraryHint()
        #expect(store.phase == .libraryHintPending)
        store.cancelPendingLibraryHint()
        #expect(store.phase == .idle)
    }

    @Test("回看时各步取备选目标与备选文案")
    func replayUsesFallbackTargets() {
        let store: OnboardingTourStore = OnboardingTourStore(defaults: Self.makeDefaults(), arguments: [])
        store.replay()
        store.advance()
        let step1: SpotlightTourStep? = store.currentStep(hasSources: true)
        #expect(step1?.focus == .anchor(.sourcesEmptyState, fallback: .sourcesInUseCard))
        #expect(step1?.cornerRadius == 28)
        store.advance()
        #expect(store.currentStep(hasSources: true)?.focus == .tabBar)
        store.advance()
        let step3: SpotlightTourStep? = store.currentStep(hasSources: true)
        #expect(step3?.focus == .anchor(.sourcesEntryCards, fallback: .sourcesActionCapsule))
        if case .tapThrough = step3?.mode {
        } else {
            Issue.record("第 3 步应是请用户点的那一步")
        }
    }

    private static func makeDefaults() -> UserDefaults {
        let suiteName: String = "OnboardingGuideTests.\(UUID().uuidString)"
        let defaults: UserDefaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
