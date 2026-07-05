import SwiftUI

// 中文注释：RootView.swift 属于应用装配和根导航，用于说明本文件承载的核心职责。

/// 中文注释：RootView 持有应用主 Tab 导航。
/// 中文注释：每个 Tab 的 ViewModel 都通过 AppContainer 创建，并用 @StateObject 保持生命周期。
struct RootView: View {
    private let container: AppContainer
    @StateObject private var sourcesViewModel: SourcesViewModel
    @StateObject private var libraryViewModel: LibraryViewModel
    @StateObject private var historyViewModel: HistoryViewModel

    init(container: AppContainer) {
        self.container = container
        _sourcesViewModel = StateObject(wrappedValue: container.makeSourcesViewModel())
        _libraryViewModel = StateObject(wrappedValue: container.makeLibraryViewModel())
        _historyViewModel = StateObject(wrappedValue: container.makeHistoryViewModel())
    }

    var body: some View {
        TabView {
            SourcesView(viewModel: self.sourcesViewModel)
                .tabItem {
                    Image(systemName: "tray.full")
                    Text("Sources")
                }

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

            HistoryView(viewModel: self.historyViewModel)
                .tabItem {
                    Image(systemName: "clock")
                    Text("History")
                }

            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape")
                    Text("Settings")
                }
        }
    }
}
