import BrowseCraftDomain
import SwiftUI

/// 中文注释：来源内搜索页。结果复用视频列表网格，点开条目走同一条详情/剧集/播放链，
/// 收藏与历史也和分类页得到的条目完全一样。
struct LibrarySearchView: View {
    @Bindable var viewModel: LibraryViewModel
    let contentViewModelFactory: LibraryContentViewModelFactory
    @FocusState private var isKeywordFocused: Bool

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
            VideoContentGridView(
                items: self.viewModel.searchResults,
                source: source,
                favoriteItemIDs: self.viewModel.favoriteItemIDs,
                favoriteAction: { item in
                    Task {
                        await self.viewModel.toggleFavorite(item: item)
                    }
                },
                nextPage: nil,
                loadNextPage: {},
                contentViewModelFactory: self.contentViewModelFactory,
                imageRequestConfig: self.viewModel.imageRequestConfig(for: source)
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
