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
    let rssContentDetailViewModelFactory: (ContentItem, Source) -> RSSContentDetailViewModel
    let videoDetailViewModelFactory: (ContentItem, Source) -> VideoDetailViewModel

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
                detailViewModelFactory: self.rssContentDetailViewModelFactory
            )
        } else if let selectedSource: Source = self.selectedSource,
                  selectedSource.configuration.kind == .video {
            VideoContentGridView(
                items: self.items,
                source: selectedSource,
                favoriteItemIDs: self.favoriteItemIDs,
                favoriteAction: self.toggleFavorite,
                detailViewModelFactory: self.videoDetailViewModelFactory,
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
            }
            .padding(16)
        }
    }
}
