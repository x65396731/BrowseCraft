import SwiftUI

// 中文注释：RSSContentListView 是 RSS 源在 Library 中的独立列表画面。

struct RSSContentListView: View {
    let items: [ContentItem]
    let source: Source
    let favoriteItemIDs: Set<String>
    let favoriteAction: (ContentItem) -> Void
    let readAction: (ContentItem) -> Void
    let contentViewModelFactory: LibraryContentViewModelFactory

    var body: some View {
        LazyVStack(spacing: 22) {
            ForEach(Array(self.items.enumerated()), id: \.offset) { _, item in
                NavigationLink(
                    destination: RSSContentDetailView(
                        item: item,
                        source: self.source,
                        factory: self.contentViewModelFactory
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
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
        .background(Self.pageBackgroundColor)
        .onAppear {
            CrashDiagnostics.shared.setScreen(.rssList)
            AppAnalytics.shared.logScreenView(.rssList)
            CrashDiagnostics.shared.setSource(self.source)
            CrashDiagnostics.shared.setRuleStage(.rssFeed)
        }
    }

    private static let pageBackgroundColor: Color = Color(
        red: 250 / 255,
        green: 250 / 255,
        blue: 252 / 255
    )
}
