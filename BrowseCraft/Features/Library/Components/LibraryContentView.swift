import BrowseCraftCore
import BrowseCraftDomain
import SwiftUI

struct LibraryContentView: View {
    let items: [ContentItem]
    let selectedSource: Source?
    let favoriteItemIDs: Set<String>
    let sourceForID: (String) -> Source?
    let toggleFavorite: (ContentItem) -> Void
    let openComic: (ContentItem, Source) -> Void
    let primaryActionTitle: (Source) -> String
    let imageRequestConfig: (Source) -> RequestConfig?
    /// 中文注释：列表下一页由 ViewModel 按 Runtime 报出的 `pagination.nextPage` 给出；影视与漫画共用。
    let nextPage: Int?
    let loadNextPage: () -> Void
    let contentViewModelFactory: LibraryContentViewModelFactory

    private let gridColumns: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    @ViewBuilder
    var body: some View {
        if let selectedSource: Source = self.selectedSource,
           selectedSource.configuration.kind == .rss {
            RSSContentListView(
                items: self.items,
                source: selectedSource,
                favoriteItemIDs: self.favoriteItemIDs,
                favoriteAction: self.toggleFavorite,
                readAction: { _ in },
                contentViewModelFactory: self.contentViewModelFactory
            )
        } else if let selectedSource: Source = self.selectedSource,
                  selectedSource.configuration.kind == .video {
            VideoContentGridView(
                items: self.items,
                source: selectedSource,
                favoriteItemIDs: self.favoriteItemIDs,
                favoriteAction: self.toggleFavorite,
                nextPage: self.nextPage,
                loadNextPage: self.loadNextPage,
                contentViewModelFactory: self.contentViewModelFactory,
                imageRequestConfig: self.imageRequestConfig(selectedSource)
            )
        } else {
            LazyVGrid(columns: self.gridColumns, spacing: 16) {
                ForEach(self.items, id: \.id) { item in
                    if let source: Source = self.sourceForID(item.sourceId) {
                        ComicLibraryCardView(
                            item: item,
                            primaryActionTitle: self.primaryActionTitle(source),
                            isFavorite: self.favoriteItemIDs.contains(item.id),
                            favoriteAction: {
                                self.toggleFavorite(item)
                            },
                            readAction: {
                                self.openComic(item, source)
                            },
                            imageRequestConfig: self.imageRequestConfig(source)
                        )
                    }
                }

                // 中文注释：触底哨兵与影视网格同形——只有 ViewModel 报出下一页时才挂上，
                // 出现在视口即请求下一页；`id` 绑定页码，翻页后哨兵换新才会再次触发。
                if let nextPage: Int = self.nextPage,
                   let selectedSource: Source = self.selectedSource {
                    Color.clear
                        .frame(height: 1)
                        .id("comic-pagination-\(selectedSource.id)-\(nextPage)")
                        .onAppear {
                            self.loadNextPage()
                        }
                }
            }
            .padding(16)
        }
    }
}
