import SwiftUI

// 中文注释：RootView.swift 属于应用装配和根导航，用于说明本文件承载的核心职责。

/// 中文注释：RootView 持有应用主 Tab 导航。
/// 中文注释：每个 Tab 的 ViewModel 都通过 AppContainer 创建，并用 @StateObject 保持生命周期。
struct RootView: View {
    private enum RootTab: Hashable {
        case sources
        case library
        case history
        case settings
    }

    private let container: AppContainer
    @StateObject private var sourcesViewModel: SourcesViewModel
    @StateObject private var libraryViewModel: LibraryViewModel
    @StateObject private var historyViewModel: HistoryViewModel
    @StateObject private var settingsViewModel: SettingsViewModel
    @State private var selectedTab: RootTab = .library

    init(container: AppContainer) {
        self.container = container
        _sourcesViewModel = StateObject(wrappedValue: container.makeSourcesViewModel())
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

            LibraryView(
                viewModel: self.libraryViewModel,
                chapterListViewModelFactory: { item, source in
                    return self.container.makeChapterListViewModel(item: item, source: source)
                },
                readerViewModelFactory: { item, source, chapter in
                    return self.container.makeReaderViewModel(
                        item: item,
                        source: source,
                        selectedChapter: chapter
                    )
                },
                feedContentDetailViewModelFactory: { item, source in
                    return self.container.makeFeedContentDetailViewModel(
                        item: item,
                        source: source
                    )
                }
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
    }
}
