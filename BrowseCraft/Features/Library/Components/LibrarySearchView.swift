import BrowseCraftDomain
import SwiftUI

/// 中文注释：来源内搜索页。结果复用分类页同一套网格（按来源 kind 分流），点开条目走同一条
/// 详情链，收藏与历史也和分类页得到的条目完全一样。
///
/// 2026-09-13 真机逮到：这里此前写死 `VideoContentGridView`，漫画来源的搜索结果被当成影视条目，
/// 点开章节走 `VideoDetailViewModel` → 「Selected source does not expose video playback runtime」。
/// 分类页从来没有这个问题，因为它经 `LibraryContentView` 按 kind 分流到 `ComicLibraryCardView`
/// 与 `ComicDetailView` / `ReaderView`。搜索页现在走同一条。
struct LibrarySearchView: View {
    @Bindable var viewModel: LibraryViewModel
    let contentViewModelFactory: LibraryContentViewModelFactory
    @FocusState private var isKeywordFocused: Bool
    @State private var selectedComicDestination: LibraryComicDestination?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search this source", text: self.$viewModel.searchKeyword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .focused(self.$isKeywordFocused)
                        .onSubmit {
                            Task {
                                await self.viewModel.performSearch()
                            }
                        }
                    if self.viewModel.searchKeyword.isEmpty == false {
                        Button {
                            self.viewModel.searchKeyword = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Clear")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                ScrollView {
                    self.results
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        self.viewModel.dismissSearch()
                    }
                }
            }
            .onAppear {
                self.isKeywordFocused = true
            }
            .navigationDestination(item: self.$selectedComicDestination) { destination in
                self.comicDestination(for: destination.item, source: destination.source)
            }
        }
    }

    /// 中文注释：与 `LibraryView.comicDestination(for:source:)` 同一分流——只有单章来源直接进阅读器。
    @ViewBuilder
    private func comicDestination(for item: ContentItem, source: Source) -> some View {
        if self.viewModel.shouldOpenReaderDirectly(for: source) {
            ReaderView(
                item: item,
                source: source,
                factory: self.contentViewModelFactory
            )
        } else {
            ComicDetailView(
                item: item,
                source: source,
                factory: self.contentViewModelFactory
            )
        }
    }

    @ViewBuilder
    private var results: some View {
        if self.viewModel.isSearching {
            ProgressView()
                .padding(.top, 48)
        } else if let message: String = self.viewModel.searchErrorMessage {
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: "Search",
                message: message
            )
            .padding(.top, 32)
        } else if let source: Source = self.viewModel.selectedSource,
                  self.viewModel.searchResults.isEmpty == false {
            LibraryContentView(
                items: self.viewModel.searchResults,
                selectedSource: source,
                favoriteItemIDs: self.viewModel.favoriteItemIDs,
                sourceForID: self.viewModel.source(for:),
                toggleFavorite: { item in
                    Task {
                        await self.viewModel.toggleFavorite(item: item)
                    }
                },
                openComic: { item, source in
                    #if DEBUG
                    AppDebugLog.write(
                        "[BrowseCraftNavigation] Select Search comic destination " +
                        "itemId=\(item.id) sourceId=\(source.id) title=\(item.title) detailURL=\(item.detailURL)"
                    )
                    #endif
                    self.selectedComicDestination = LibraryComicDestination(item: item, source: source)
                },
                primaryActionTitle: self.viewModel.primaryActionTitle(for:),
                imageRequestConfig: self.viewModel.imageRequestConfig(for:),
                // 中文注释：搜索结果页的分页由 `searchRules[].pagination` 声明；当前搜索规则不带分页时
                // ViewModel 不报下一页，网格也就不挂触底哨兵。
                nextPage: nil,
                loadNextPage: {},
                contentViewModelFactory: self.contentViewModelFactory
            )
        } else if self.viewModel.hasSearched {
            EmptyStateView(
                systemImage: "magnifyingglass",
                title: "No results",
                message: "Try another keyword."
            )
            .padding(.top, 32)
        } else {
            EmptyStateView(
                systemImage: "magnifyingglass",
                title: "Search",
                message: "Enter a keyword to search this source."
            )
            .padding(.top, 32)
        }
    }
}
