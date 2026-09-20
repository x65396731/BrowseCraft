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

    private let libraryContentViewModelFactory: LibraryContentViewModelFactory
    private let browserRequestHeaderProvider: any BrowserRequestHeaderProviding
    private let systemCookieHeaderProvider: any SystemCookieHeaderProviding
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
                        return try await sourcesViewModel.loadForStartup()
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
        .task {
            self.startupCoordinator.start()
        }
        .task {
            await self.cloudSyncSettingsViewModel.start()
        }
        .onChange(of: self.sourcesViewModel.latestSourceAddID) { _, sourceID in
            guard sourceID != nil else {
                return
            }

            DispatchQueue.main.async {
                self.selectedTab = .library
            }
        }
        // 中文注释：点开生成推送 → 只有主界面就绪（启动动画已结束）才切到 Sources 并打开
        // 「规则目录」；冷启动时先留作待处理，启动动画结束那一刻再消费。
        .onChange(of: self.sourcesViewModel.catalogPresentationRevision) { _, _ in
            self.navigateToCatalogIfPending()
        }
        .onChange(of: self.startupCoordinator.phase.isDismissed) { _, dismissed in
            if dismissed {
                self.navigateToCatalogIfPending()
            }
        }
        #if DEBUG
        .onChange(of: self.startupCoordinator.phase.canSkip) { _, canSkip in
            if canSkip && Self.skipsStartupAnimationWhenUnlocked {
                self.skipStartupAnimation()
            }
        }
        #endif
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
                cloudSyncViewModel: self.cloudSyncSettingsViewModel
            )
                .tabItem {
                    Image("TabSources")
                    Text("Sources")
                }
                .tag(RootTab.sources)

            FavoritesView(
                viewModel: self.favoritesViewModel,
                cloudSyncViewModel: self.cloudSyncSettingsViewModel,
                contentViewModelFactory: self.libraryContentViewModelFactory
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
                contentViewModelFactory: self.libraryContentViewModelFactory
            )
                .tabItem {
                    Image("TabHistory")
                    Text("History")
                }
                .tag(RootTab.history)

            SettingsView(
                viewModel: self.settingsViewModel,
                cloudSyncViewModel: self.cloudSyncSettingsViewModel
            )
                .tabItem {
                    Image("TabSettings")
                    Text("Settings")
                }
                .tag(RootTab.settings)
        }
    }

    private func skipStartupAnimation() {
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
        }
        self.navigateToCatalogIfPending()
    }

    private func navigateToCatalogIfPending() {
        guard self.startupCoordinator.phase.isDismissed,
              self.sourcesViewModel.pendingCatalogPresentation else {
            return
        }
        self.selectedTab = .sources
        // 中文注释：等 tab 切换提交后再弹表单，否则 sheet 会挂在还没显示的 tab 上。
        DispatchQueue.main.async {
            self.sourcesViewModel.presentCatalogSheetIfPending()
        }
    }
}
