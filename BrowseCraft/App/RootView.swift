import BrowseCraftDomain
import SwiftUI

// 中文注释：RootView.swift 属于应用装配和根导航，用于说明本文件承载的核心职责。

/// 中文注释：RootView 持有应用主 Tab 导航。
/// 中文注释：每个 Tab 的 ViewModel 都通过 AppContainer 创建，并用 @StateObject 保持生命周期。
@MainActor
struct RootView: View {
    private enum RootTab: Hashable {
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
        .onChange(of: self.cloudSyncSettingsViewModel.identityRevision) { _, _ in
            Task {
                await self.historyViewModel.load()
                await self.libraryViewModel.reloadForActiveUserChange()
            }
        }
    }

    private var mainTabView: some View {
        TabView(selection: self.$selectedTab) {
            SourcesView(
                viewModel: self.sourcesViewModel,
                cloudSyncViewModel: self.cloudSyncSettingsViewModel
            )
                .tabItem {
                    Image(systemName: "tray.full")
                    Text("Sources")
                }
                .tag(RootTab.sources)

            FavoritesView(
                viewModel: self.favoritesViewModel,
                cloudSyncViewModel: self.cloudSyncSettingsViewModel,
                contentViewModelFactory: self.libraryContentViewModelFactory
            )
                .tabItem {
                    Image(systemName: "heart")
                    Text("Favorites")
                }
                .tag(RootTab.favorites)

            LibraryView(
                viewModel: self.libraryViewModel,
                contentViewModelFactory: self.libraryContentViewModelFactory
            )
                .tabItem {
                    Image(systemName: "square.grid.2x2")
                    Text("Library")
                }
                .tag(RootTab.library)

            HistoryView(
                viewModel: self.historyViewModel,
                contentViewModelFactory: self.libraryContentViewModelFactory
            )
                .tabItem {
                    Image(systemName: "clock")
                    Text("History")
                }
                .tag(RootTab.history)

            SettingsView(
                viewModel: self.settingsViewModel,
                cloudSyncViewModel: self.cloudSyncSettingsViewModel
            )
                .tabItem {
                    Image(systemName: "gearshape")
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
