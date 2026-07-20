import SwiftUI

// 中文注释：RootView.swift 属于应用装配和根导航，用于说明本文件承载的核心职责。

/// 中文注释：RootView 持有应用主 Tab 导航。
/// 中文注释：每个 Tab 的 ViewModel 都通过 AppContainer 创建，并用 @StateObject 保持生命周期。
struct RootView: View {
    private enum RootTab: Hashable {
        case sources
        case favorites
        case library
        case history
        case settings
    }

    private let container: AppContainer
    @StateObject private var sourcesViewModel: SourcesViewModel
    @StateObject private var favoritesViewModel: FavoritesViewModel
    @StateObject private var libraryViewModel: LibraryViewModel
    @StateObject private var historyViewModel: HistoryViewModel
    @StateObject private var settingsViewModel: SettingsViewModel
    @State private var selectedTab: RootTab = .library
    @State private var didResolveInitialTab: Bool = false

    private var libraryContentViewModelFactory: LibraryContentViewModelFactory {
        return LibraryContentViewModelFactory(
            makeComicDetail: { item, source in
                return self.container.makeComicDetailViewModel(item: item, source: source)
            },
            makeReader: { item, source, chapter in
                return self.container.makeReaderViewModel(
                    item: item,
                    source: source,
                    selectedChapter: chapter
                )
            },
            makeHistoryReader: { history, source in
                return self.container.makeReaderViewModel(history: history, source: source)
            },
            makeRSSDetail: { item, source in
                return self.container.makeRSSContentDetailViewModel(
                    item: item,
                    source: source
                )
            },
            makeVideoDetail: { item, source in
                return self.container.makeVideoDetailViewModel(
                    item: item,
                    source: source
                )
            }
        )
    }

    init(container: AppContainer) {
        self.container = container
        _sourcesViewModel = StateObject(wrappedValue: container.makeSourcesViewModel())
        _favoritesViewModel = StateObject(wrappedValue: container.makeFavoritesViewModel())
        _libraryViewModel = StateObject(wrappedValue: container.makeLibraryViewModel())
        _historyViewModel = StateObject(wrappedValue: container.makeHistoryViewModel())
        _settingsViewModel = StateObject(wrappedValue: container.makeSettingsViewModel())
    }

    var body: some View {
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
                readerViewModelFactory: { history, source in
                    return self.container.makeReaderViewModel(history: history, source: source)
                }
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
        .onAppear {
            DispatchQueue.main.async {
                self.resolveInitialTabIfNeeded()
            }
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

    private func resolveInitialTabIfNeeded() {
        if self.didResolveInitialTab {
            return
        }

        self.didResolveInitialTab = true
        self.sourcesViewModel.load()
        if self.sourcesViewModel.sources.isEmpty {
            self.selectedTab = .sources
        }
    }
}
