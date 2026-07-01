import SwiftUI

/// RootView owns the main tab navigation.
///
/// It creates one ViewModel per tab through AppContainer. We keep those
/// ViewModels in @StateObject so SwiftUI preserves them while the view refreshes.
struct RootView: View {
    @StateObject private var sourcesViewModel: SourcesViewModel
    @StateObject private var libraryViewModel: LibraryViewModel
    @StateObject private var historyViewModel: HistoryViewModel

    init(container: AppContainer) {
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

            LibraryView(viewModel: self.libraryViewModel)
                .tabItem {
                    Image(systemName: "square.grid.2x2")
                    Text("Library")
                }

            HistoryView(viewModel: self.historyViewModel)
                .tabItem {
                    Image(systemName: "clock")
                    Text("History")
                }
        }
    }
}
