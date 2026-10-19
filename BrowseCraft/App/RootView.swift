import BrowseCraftDomain
import SwiftUI

// 中文注释：RootView.swift 属于应用装配和根导航，用于说明本文件承载的核心职责。

/// 中文注释：RootView 持有应用主 Tab 导航。
/// 中文注释：每个 Tab 的 ViewModel 都通过 AppContainer 创建，并用 @StateObject 保持生命周期。
@MainActor
struct RootView: View {
    private enum RootTab: String, Hashable {
        case sources
        case favorites
        case library
        case history
        case settings
    }

    @Environment(\.scenePhase) private var scenePhase
    private let libraryContentViewModelFactory: LibraryContentViewModelFactory
    private let browserRequestHeaderProvider: any BrowserRequestHeaderProviding
    private let systemCookieHeaderProvider: any SystemCookieHeaderProviding
    private let coinWalletStore: CoinWalletStore
    private let problemReportUseCase: SubmitProblemReportUseCase
    private let contentLockStore: ContentLockStore
    #if DEBUG
    private let videoRuntimeAuditWebUIPresenter: VideoRuntimeAuditWebUIPresenter
    /// 中文注释：仅 DEBUG——模拟器注入的 tap 打不到开屏「跳过」按钮；带启动参数
    /// `-BrowseCraftSkipStartupAnimation` 时，跳过一解锁就自动走与按钮相同的 skip 路径，供模拟器验证。
    private static let skipsStartupAnimationWhenUnlocked: Bool =
        ProcessInfo.processInfo.arguments.contains("-BrowseCraftSkipStartupAnimation")
    /// 中文注释：仅 DEBUG——`-BrowseCraftInitialTab <标签>` 指定跳过开屏后停在哪个 tab，标签即 `RootTab` 的原始值，
    /// 因此新增 tab 不必改这里。模拟器注入的 tap 需要设备授权，这个参数让逐页验证不依赖授权；
    /// 未传参或标签无效时保持既有落点。
    private static let debugInitialTab: RootTab? = {
        let arguments: [String] = ProcessInfo.processInfo.arguments
        guard let flagIndex: Int = arguments.firstIndex(of: "-BrowseCraftInitialTab") else {
            return nil
        }
        let valueIndex: Int = arguments.index(after: flagIndex)
        guard valueIndex < arguments.endIndex else {
            return nil
        }
        return RootTab(rawValue: arguments[valueIndex])
    }()
    #endif
    @State private var sourcesViewModel: SourcesViewModel
    @State private var favoritesViewModel: FavoritesViewModel
    @State private var libraryViewModel: LibraryViewModel
    @State private var historyViewModel: HistoryViewModel
    @State private var settingsViewModel: SettingsViewModel
    @State private var cloudSyncSettingsViewModel: CloudSyncSettingsViewModel
    @State private var startupCoordinator: StartupCoordinator
    @State private var selectedTab: RootTab = .library

    init(container: AppContainer) {
        let sourcesViewModel: SourcesViewModel = container.makeSourcesViewModel()
        let libraryViewModel: LibraryViewModel = container.makeLibraryViewModel()

        self.browserRequestHeaderProvider = container.browserRequestHeaderProvider
        self.systemCookieHeaderProvider = container.systemCookieHeaderProvider
        self.coinWalletStore = container.coinWalletStore
        self.problemReportUseCase = container.problemReportUseCase
        self.contentLockStore = container.contentLockStore
        #if DEBUG
        self.videoRuntimeAuditWebUIPresenter = container.videoRuntimeAuditWebUIPresenter
        #endif
        self.libraryContentViewModelFactory = container.makeLibraryContentViewModelFactory()
        _sourcesViewModel = State(wrappedValue: sourcesViewModel)
        _favoritesViewModel = State(wrappedValue: container.makeFavoritesViewModel())
        _libraryViewModel = State(wrappedValue: libraryViewModel)
        _historyViewModel = State(wrappedValue: container.makeHistoryViewModel())
        _settingsViewModel = State(wrappedValue: container.makeSettingsViewModel())
        _cloudSyncSettingsViewModel = State(
            wrappedValue: container.makeCloudSyncSettingsViewModel()
        )
        _startupCoordinator = State(
            wrappedValue: StartupCoordinator(
                dependencies: StartupCoordinator.Dependencies(
                    hasSources: {
                        let hasSources: Bool = try await sourcesViewModel.loadForStartup()
                        // 中文注释：已添加的来源跟随公共目录；不阻塞启动，读完在后台静默覆盖。
                        Task { @MainActor in
                            await sourcesViewModel.syncAddedSourcesWithCatalog()
                        }
                        return hasSources
                    },
                    loadSelectedSource: {
                        return await libraryViewModel.loadIfNeeded()
                    }
                )
            )
        )
    }

    var body: some View {
        ZStack {
            self.mainTabView
                .allowsHitTesting(self.startupCoordinator.phase.isDismissed)
                .accessibilityHidden(self.startupCoordinator.phase.isDismissed == false)

            if self.startupCoordinator.phase.isDismissed == false {
                StartupAnimationView(
                    phase: self.startupCoordinator.phase,
                    skipAction: self.skipStartupAnimation,
                    videoFailureAction: self.startupCoordinator.reportVideoPlaybackFailure
                )
                .transition(.opacity)
                .zIndex(1)
            }

            #if DEBUG
            // 中文注释：BC-EVIDENCE-077.6——显式 runtime audit 的前台 WebUI 覆盖层位于启动动画之上；
            // 无 audit session 时不渲染。
            VideoRuntimeAuditWebUIOverlay(presenter: self.videoRuntimeAuditWebUIPresenter)
                .zIndex(2)
            #endif
        }
        .environment(\.browserRequestHeaderProvider, self.browserRequestHeaderProvider)
        .environment(\.itemThumbnailImagePipeline, ItemThumbnailImageCachePlugin.shared)
        .environment(\.systemCookieHeaderProvider, self.systemCookieHeaderProvider)
        .environment(\.rewardedAdRewardCoordinator, self.coinWalletStore)
        .environment(\.problemReportSubmitter, self.problemReportUseCase)
        .task {
            self.startupCoordinator.start()
        }
        .task {
            await self.cloudSyncSettingsViewModel.start()
        }
        .onChange(of: self.scenePhase) { _, phase in
            // 中文注释：收藏与历史锁定（`docs/design/Content-Lock-Design.md` 第四节）：非活跃时盖上、进入后台即重新锁定，
            // 回到前台且停在这两页之一时自动拉起一次验证（验证本身引起的那次活跃除外）。
            switch phase {
            case .inactive:
                self.contentLockStore.sceneDidBecomeInactive()
            case .background:
                self.contentLockStore.sceneDidEnterBackground()
            case .active:
                if self.contentLockStore.sceneDidBecomeActive() {
                    self.promptContentUnlockIfNeeded(trigger: .foreground)
                }
            @unknown default:
                break
            }
            // 中文注释：回到前台时让已添加的来源跟上公共目录；间隔节流在 `syncAddedSourcesWithCatalog` 里。
            guard phase == .active else {
                return
            }
            Task {
                await self.sourcesViewModel.syncAddedSourcesWithCatalog()
            }
        }
        .onChange(of: self.selectedTab) { _, _ in
            // 中文注释：切到锁着的收藏或历史时自动拉起一次验证；取消后停在锁定态，等下次切进来或回到前台。
            self.promptContentUnlockIfNeeded(trigger: .tabSwitch)
        }
        .onChange(of: self.sourcesViewModel.latestSourceAddID) { _, sourceID in
            guard sourceID != nil else {
                return
            }

            DispatchQueue.main.async {
                self.selectedTab = .library
            }
        }
        #if DEBUG
        .onChange(of: self.startupCoordinator.phase.canSkip) { _, canSkip in
            if canSkip && Self.skipsStartupAnimationWhenUnlocked {
                self.skipStartupAnimation()
            }
        }
        #endif
        .onChange(of: self.favoritesViewModel.changeRevision) { _, _ in
            // 中文注释：收藏页取消 / 撤销收藏后，库页封面上的爱心状态跟着刷新。
            self.libraryViewModel.refreshFavoriteItemIDs()
        }
        .onChange(of: self.sourcesViewModel.sourceContentRevision) { _, _ in
            // 中文注释：来源页删除 / 撤销删除来源后历史与收藏保留（`BCA-DB-005`），但被删来源的行要变成「来源已删除」或恢复正常，
            // 历史页、收藏页重新载入。库页的爱心与「上次看到」只看当前来源，不受影响。
            Task {
                await self.historyViewModel.load()
                await self.favoritesViewModel.load()
            }
        }
        .onChange(of: self.cloudSyncSettingsViewModel.identityRevision) { _, _ in
            Task {
                await self.historyViewModel.load()
                await self.libraryViewModel.reloadForActiveUserChange()
            }
        }
    }

    /// 中文注释：底栏五图标是自绘的纯黑剪影，走资产目录里标好的模板渲染——
    /// `tabItem` 的 `Image` 本来就只取 alpha 再填 tint 色，所以选中/未选中的着色仍由系统负责，
    /// 行为与换掉的那五个 SF Symbol 一致，这里不写 `.renderingMode`。
    /// 代价是位图不跟 Dynamic Type 缩放——换来的是形状归自己。
    private var mainTabView: some View {
        TabView(selection: self.$selectedTab) {
            SourcesView(
                viewModel: self.sourcesViewModel,
                cloudSyncViewModel: self.cloudSyncSettingsViewModel,
                // 中文注释：点来源即打开库（`docs/design/Sources-Page-Redesign-Design.md` 2.3），
                // 与 `latestSourceAddID` 触发的跳转同一处切标签。
                openLibrary: {
                    self.selectedTab = .library
                },
                // 中文注释：来源位置不够时的「更多位置」进入设置页既有的高级版购买入口。
                openPremium: {
                    self.settingsViewModel.requestInAppPurchase()
                    self.selectedTab = .settings
                }
            )
                .tabItem {
                    Image("TabSources")
                    Text("Sources")
                }
                .tag(RootTab.sources)

            FavoritesView(
                viewModel: self.favoritesViewModel,
                cloudSyncViewModel: self.cloudSyncSettingsViewModel,
                contentLockStore: self.contentLockStore,
                contentViewModelFactory: self.libraryContentViewModelFactory,
                openLibrary: {
                    self.selectedTab = .library
                },
                openSourceInLibrary: { source in
                    self.openSourceInLibrary(source, activationEntry: .favorites)
                },
                requestSourceActivation: { source in
                    self.requestSourceActivation(source, entry: .favorites)
                }
            )
                .tabItem {
                    Image("TabFavorites")
                    Text("Favorites")
                }
                .tag(RootTab.favorites)

            LibraryView(
                viewModel: self.libraryViewModel,
                contentViewModelFactory: self.libraryContentViewModelFactory)
                .tabItem {
                    Image("TabLibrary")
                    Text("Library")
                }
                .tag(RootTab.library)

            HistoryView(
                viewModel: self.historyViewModel,
                contentLockStore: self.contentLockStore,
                contentViewModelFactory: self.libraryContentViewModelFactory,
                openLibrary: {
                    self.selectedTab = .library
                },
                openSourceInLibrary: { source in
                    self.openSourceInLibrary(source, activationEntry: .history)
                },
                requestSourceActivation: { source in
                    self.requestSourceActivation(source, entry: .history)
                }
            )
                .tabItem {
                    Image("TabHistory")
                    Text("History")
                }
                .tag(RootTab.history)

            SettingsView(
                viewModel: self.settingsViewModel,
                cloudSyncViewModel: self.cloudSyncSettingsViewModel,
                contentLockStore: self.contentLockStore
            )
                .tabItem {
                    Image("TabSettings")
                    Text("Settings")
                }
                .tag(RootTab.settings)
        }
    }

    /// 中文注释：当前停在收藏或历史、且这两页锁着时拉起一次验证；开屏动画还在时不拉。
    private func promptContentUnlockIfNeeded(trigger: ContentUnlockTrigger) {
        guard self.startupCoordinator.phase.isDismissed,
              self.selectedTab == .favorites || self.selectedTab == .history,
              self.contentLockStore.isContentHidden else {
            return
        }
        Task {
            let result: DeviceOwnerAuthenticationResult? = await self.contentLockStore.unlock(
                reason: NSLocalizedString("content_lock_reason_unlock", comment: "解锁时的验证说明")
            )
            ContentLockedView.logUnlockResult(result, trigger: trigger)
        }
    }

    /// 中文注释：收藏页与历史页长按「在库中查看来源」——与来源页「点来源即打开库」同一条路径：
    /// 已暂停的来源转到来源页的启用窗口；切换成功切到库；切换失败切到来源页，错误弹窗与重试在那里。
    /// `open_in_library_tapped` 由收藏页 / 历史页在菜单里报；这里只给随后的来源切换与启用带上入口。
    private func openSourceInLibrary(_ source: Source, activationEntry: SourceActivationEntry) {
        let current: Source = self.sourcesViewModel.source(id: source.id) ?? source
        if current.accessState == .lockedBySlotLimit {
            self.requestSourceActivation(current, entry: activationEntry)
            return
        }
        Task {
            if await self.sourcesViewModel.selectSourceAfterRefresh(current, entry: .openInLibrary) {
                self.selectedTab = .library
            } else if self.sourcesViewModel.errorMessage != nil {
                self.selectedTab = .sources
            }
        }
    }

    /// 中文注释：点已暂停来源的收藏或历史——启用来源窗口挂在来源页上，所以先切到来源页再请求。
    private func requestSourceActivation(_ source: Source, entry: SourceActivationEntry) {
        let current: Source = self.sourcesViewModel.source(id: source.id) ?? source
        self.sourcesViewModel.requestSlotActivation(for: current, entry: entry)
        self.selectedTab = .sources
    }

    private func skipStartupAnimation() {
        // 中文注释：跳过按钮只在解锁后出现，开屏总是由它结束；解锁原因就是开屏为什么结束。
        let unlockReason: StartupUnlockReason?
        if case .unlocked(let reason, _) = self.startupCoordinator.phase {
            unlockReason = reason
        } else {
            unlockReason = nil
        }
        withAnimation(.easeOut(duration: 0.28)) {
            guard let destination: StartupDestination = self.startupCoordinator.skip() else {
                return
            }

            switch destination {
            case .sources:
                self.selectedTab = .sources
            case .library:
                self.selectedTab = .library
            }

            #if DEBUG
            if let initialTab: RootTab = Self.debugInitialTab {
                self.selectedTab = initialTab
            }
            #endif

            AppAnalytics.shared.logStartupFinished(
                outcome: Self.startupOutcome(for: unlockReason),
                landingTab: Self.analyticsTab(for: self.selectedTab)
            )
        }
    }

    /// 中文注释：开屏只能在解锁后由用户点「跳过」结束，所以报解锁原因；拿不到解锁原因（理论上不会发生）时报 skipped。
    private static func startupOutcome(for reason: StartupUnlockReason?) -> StartupOutcome {
        switch reason {
        case .sourceLoaded:
            return .loaded
        case .sourceLoadFailed:
            return .sourceLoadFailed
        case .noSources:
            return .noSources
        case .sourceCheckFailed:
            return .sourceCheckFailed
        case .sourceLoadTimedOut:
            return .timedOut
        case .videoPlaybackFailed:
            return .videoFailed
        case nil:
            return .skipped
        }
    }

    private static func analyticsTab(for tab: RootTab) -> AnalyticsTab {
        switch tab {
        case .sources:
            return .sources
        case .favorites:
            return .favorites
        case .library:
            return .library
        case .history:
            return .history
        case .settings:
            return .settings
        }
    }
}
