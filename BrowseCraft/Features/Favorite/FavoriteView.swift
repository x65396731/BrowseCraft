import SwiftUI

// 中文注释：FavoriteView 是独立收藏页，结构上和 History 页并列。

struct FavoriteView: View {
    @ObservedObject var viewModel: FavoriteViewModel
    let chapterListViewModelFactory: (ContentItem, Source) -> ChapterListViewModel
    let readerViewModelFactory: (ContentItem, Source, ChapterLink?) -> ReaderViewModel
    let rssContentDetailViewModelFactory: (ContentItem, Source) -> RSSContentDetailViewModel
    let videoDetailViewModelFactory: (ContentItem, Source) -> VideoDetailViewModel

    var body: some View {
        NavigationStack {
            List {
                Section("Favorites") {
                    ForEach(self.viewModel.favoriteItems, id: \.id) { item in
                        if let source: Source = self.viewModel.source(for: item) {
                            NavigationLink(value: FavoriteDestination(item: item, source: source)) {
                                FavoriteEntryRowView(
                                    item: item,
                                    sourceName: self.viewModel.sourceName(for: item),
                                    dateText: Self.favoriteDateFormatter.string(from: item.favoritedAt ?? item.updatedAt ?? Date())
                                )
                            }
                        } else {
                            FavoriteEntryRowView(
                                item: item,
                                sourceName: "Unknown Source",
                                dateText: Self.favoriteDateFormatter.string(from: item.favoritedAt ?? item.updatedAt ?? Date())
                            )
                        }
                    }
                }
            }
            .navigationDestination(for: FavoriteDestination.self) { destination in
                self.destination(for: destination.item, source: destination.source)
            }
            .overlay(
                Group {
                    if self.viewModel.favoriteItems.isEmpty {
                        EmptyStateView(
                            systemImage: "heart",
                            title: "No Favorites",
                            message: "Items you favorite will appear here."
                        )
                    }
                }
            )
            .navigationTitle("Favorites")
            .onAppear {
                CrashDiagnostics.shared.setScreen(.favorite)
                AppAnalytics.shared.logScreenView(.favorite)
                self.viewModel.load()
            }
            .alert(isPresented: self.errorAlertBinding) {
                Alert(
                    title: Text("Favorites"),
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

    @ViewBuilder
    private func destination(for item: FavoriteContentItem, source: Source) -> some View {
        let contentItem: ContentItem = item.contentItem()
        switch item.kind {
        case .rss:
            RSSContentDetailView(viewModel: self.rssContentDetailViewModelFactory(contentItem, source))
        case .comic:
            ChapterListView(
                viewModel: self.chapterListViewModelFactory(contentItem, source),
                readerViewModelFactory: self.readerViewModelFactory
            )
        case .videoNative, .videoWeb:
            VideoDetailView(viewModel: self.videoDetailViewModelFactory(contentItem, source))
        }
    }

    private static let favoriteDateFormatter: DateFormatter = {
        let formatter: DateFormatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private var errorAlertBinding: Binding<Bool> {
        Binding<Bool>(
            get: {
                self.viewModel.errorMessage != nil
            },
            set: { newValue in
                if newValue == false {
                    self.viewModel.errorMessage = nil
                }
            }
        )
    }
}

private struct FavoriteDestination: Hashable {
    let item: FavoriteContentItem
    let source: Source
}

private struct FavoriteEntryRowView: View {
    let item: FavoriteContentItem
    let sourceName: String
    let dateText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: self.iconName)
                    .foregroundColor(.secondary)
                    .frame(width: 18)

                Text(self.item.title)
                    .font(.body.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
            }

            Text(self.sourceName)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)

            if let detail: String = self.detailText {
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }

            Text(self.dateText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        switch self.item.kind {
        case .rss:
            return "dot.radiowaves.left.and.right"
        case .comic:
            return "book.pages"
        case .videoNative, .videoWeb:
            return "play.rectangle"
        }
    }

    private var detailText: String? {
        if let latestText: String = self.item.latestText {
            return latestText
        }

        return self.item.detailURL
    }
}
