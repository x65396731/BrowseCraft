import SwiftUI

// 中文注释：VideoContentGridView 是 Library 的视频源列表，不复用漫画卡片入口。
struct VideoContentGridView: View {
    let items: [ContentItem]
    let source: Source
    let favoriteItemIDs: Set<String>
    let favoriteAction: (ContentItem) -> Void
    let detailViewModelFactory: (ContentItem, Source) -> VideoDetailViewModel
    let imageRequestConfig: RequestConfig?

    private let gridColumns: [GridItem] = [
        GridItem(.adaptive(minimum: 160), spacing: 14)
    ]

    var body: some View {
        LazyVGrid(columns: self.gridColumns, spacing: 16) {
            ForEach(Array(self.items.enumerated()), id: \.offset) { _, item in
                NavigationLink(
                    destination: VideoDetailView(
                        viewModel: self.detailViewModelFactory(item, self.source)
                    ),
                    label: {
                        VideoLibraryCardView(
                            item: item,
                            sourceName: self.source.name,
                            isFavorite: self.favoriteItemIDs.contains(item.id),
                            favoriteAction: {
                                self.favoriteAction(item)
                            },
                            imageRequestConfig: self.imageRequestConfig
                        )
                    }
                )
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .onAppear {
            #if DEBUG
            print(
                "[BrowseCraftVideoUI] grid appear " +
                "source=\(self.source.id) " +
                "kind=\(self.source.configuration.kind.rawValue) " +
                "items=\(self.items.count) " +
                "firstItem=\(self.items.first?.id ?? "nil")"
            )
            #endif
        }
    }
}

private struct VideoLibraryCardView: View {
    let item: ContentItem
    let sourceName: String
    let isFavorite: Bool
    let favoriteAction: () -> Void
    let imageRequestConfig: RequestConfig?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                ItemThumbnailImageView(
                    urlString: self.item.coverURL,
                    refererURLString: self.item.detailURL,
                    requestConfig: self.imageRequestConfig
                )
                .aspectRatio(0.72, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Button(
                    action: {
                        self.favoriteAction()
                    },
                    label: {
                        Image(systemName: self.isFavorite ? "star.fill" : "star")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(self.isFavorite ? .yellow : .white)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.45))
                            )
                    }
                )
                .buttonStyle(.plain)
                .padding(6)
                .accessibilityLabel(self.isFavorite ? "Remove Favorite" : "Add Favorite")
            }

            Text(self.item.title)
                .font(.headline)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Label(
                    title: {
                        Text("Video")
                    },
                    icon: {
                        Image(systemName: "play.rectangle")
                    }
                )

                Text(self.sourceName)
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundColor(.secondary)

            if let latestText: String = self.item.latestText {
                Text(latestText)
                    .font(.caption)
                    .foregroundColor(.blue)
                    .lineLimit(1)
            }

            Label("Episodes", systemImage: "list.bullet.rectangle")
                .font(.callout.weight(.semibold))
                .foregroundColor(.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
        }
        .padding(10)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(.separator), lineWidth: 1)
        )
    }
}
