import SwiftUI

// 中文注释：RSSContentListView 是 RSS 源在 Library 中的独立列表画面。

struct RSSContentListView: View {
    let items: [ContentItem]
    let source: Source
    let favoriteItemIDs: Set<String>
    let favoriteAction: (ContentItem) -> Void
    let readAction: (ContentItem) -> Void
    let detailViewModelFactory: (ContentItem, Source) -> RSSContentDetailViewModel

    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach(self.items, id: \.id) { item in
                NavigationLink(
                    destination: RSSContentDetailView(
                        viewModel: self.detailViewModelFactory(item, self.source)
                    ),
                    label: {
                        RSSContentRowView(
                            item: item,
                            sourceName: self.source.name,
                            isFavorite: self.favoriteItemIDs.contains(item.id),
                            favoriteAction: {
                                self.favoriteAction(item)
                            }
                        )
                    }
                )
                .buttonStyle(.plain)
                .simultaneousGesture(
                    TapGesture().onEnded {
                        #if DEBUG
                        print(
                            "[BrowseCraftNavigation] Tap RSS article " +
                            "itemId=\(item.id) " +
                            "title=\(item.title) " +
                            "detailURL=\(item.detailURL)"
                        )
                        #endif

                        self.readAction(item)
                    }
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onAppear {
            CrashDiagnostics.shared.setScreen(.rssList)
            CrashDiagnostics.shared.setSource(self.source)
            CrashDiagnostics.shared.setRuleStage(.rssFeed)
        }
    }
}
