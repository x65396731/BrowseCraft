import SwiftUI

// 中文注释：LibraryView.swift 属于界面功能层，用于说明本文件承载的核心职责。

/// 中文注释：LibraryView 是 struct，负责本模块中的对应职责。
struct LibraryView: View {
    @ObservedObject var viewModel: LibraryViewModel
    let chapterListViewModelFactory: (ContentItem, Source) -> ChapterListViewModel
    let readerViewModelFactory: (ContentItem, Source, ChapterLink?) -> ReaderViewModel

    private let gridColumns: [GridItem] = [
        GridItem(.adaptive(minimum: 150), spacing: 14)
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: self.gridColumns, spacing: 16) {
                    ForEach(self.viewModel.items, id: \.id) { item in
                        if let source: Source = self.viewModel.source(for: item.sourceId) {
                            ContentCardView(
                                item: item,
                                sourceName: source.name,
                                isFavorite: self.viewModel.favoriteItemIDs.contains(item.id),
                                favoriteAction: {
                                    self.viewModel.toggleFavorite(item: item)
                                },
                                readAction: {
                                    self.viewModel.recordOpened(item: item)
                                },
                                readerDestination: ChapterListView(
                                    viewModel: self.chapterListViewModelFactory(item, source),
                                    readerViewModelFactory: self.readerViewModelFactory
                                )
                            )
                        }
                    }
                }
                .padding(16)
            }
            .overlay(
                Group {
                if self.viewModel.items.isEmpty {
                    EmptyStateView(
                        systemImage: "square.grid.2x2",
                        title: "No Items",
                        message: "Refresh a source to fill your library."
                    )
                }
                }
            )
            .navigationTitle("Library")
            .onAppear {
                self.viewModel.load()
            }
            .alert(isPresented: self.errorAlertBinding) {
                Alert(
                    title: Text("Library"),
                    message: Text(self.viewModel.errorMessage ?? ""),
                    dismissButton: .default(
                        Text("OK"),
                        action: {
                            self.viewModel.errorMessage = nil
                        }
                    )
                )
            }
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        return Binding<Bool>(
            get: {
                return self.viewModel.errorMessage != nil
            },
            set: { newValue in
                if newValue == false {
                    self.viewModel.errorMessage = nil
                }
            }
        )
    }
}
