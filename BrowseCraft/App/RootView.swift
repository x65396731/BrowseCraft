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
    @StateObject private var sourcesViewModel: SourcesViewModel
    @StateObject private var favoritesViewModel: FavoritesViewModel
    @StateObject private var libraryViewModel: LibraryViewModel
    @StateObject private var historyViewModel: HistoryViewModel
    @StateObject private var settingsViewModel: SettingsViewModel
    @StateObject private var startupCoordinator: StartupCoordinator
    @State private var selectedTab: RootTab = .library

    init(container: AppContainer) {
        let sourcesViewModel: SourcesViewModel = container.makeSourcesViewModel()
        let libraryViewModel: LibraryViewModel = container.makeLibraryViewModel()

        self.browserRequestHeaderProvider = container.browserRequestHeaderProvider
        self.systemCookieHeaderProvider = container.systemCookieHeaderProvider
        self.libraryContentViewModelFactory = container.makeLibraryContentViewModelFactory()
        _sourcesViewModel = StateObject(wrappedValue: sourcesViewModel)
        _favoritesViewModel = StateObject(wrappedValue: container.makeFavoritesViewModel())
        _libraryViewModel = StateObject(wrappedValue: libraryViewModel)
        _historyViewModel = StateObject(wrappedValue: container.makeHistoryViewModel())
        _settingsViewModel = StateObject(wrappedValue: container.makeSettingsViewModel())
        _startupCoordinator = StateObject(
            wrappedValue: StartupCoordinator(
                dependencies: StartupCoordinator.Dependencies(
                    hasSources: {
                        return try sourcesViewModel.loadForStartup()
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
        }
        .environment(\.browserRequestHeaderProvider, self.browserRequestHeaderProvider)
        .environment(\.systemCookieHeaderProvider, self.systemCookieHeaderProvider)
        .task {
            self.startupCoordinator.start()
        }
        .task {
            await self.settingsViewModel.observeStoreKitTransactions()
        }
        .onChange(of: self.sourcesViewModel.latestSourceAddID) { _, sourceID in
            guard sourceID != nil else {
                return
            }

            DispatchQueue.main.async {
                self.selectedTab = .library
            }
        }
    }

    private var mainTabView: some View {
        TabView(selection: self.$selectedTab) {
            SourcesView(viewModel: self.sourcesViewModel)
                .tabItem {
                    Image(systemName: "tray.full")
                    Text("Sources")
                }
                .tag(RootTab.sources)

            FavoritesView(
                viewModel: self.favoritesViewModel,
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

            SettingsView(viewModel: self.settingsViewModel)
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
    }
}
