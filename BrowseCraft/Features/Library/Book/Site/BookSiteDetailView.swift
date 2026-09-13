import BrowseCraftDomain
import SwiftUI

// 中文注释：BookSiteDetailView：站点作品的详情页——头部、开始 / 继续阅读、章节列表；章节推入共用的 EPUB 阅读器。

struct BookSiteDetailView: View {
    @State private var viewModel: BookSiteDetailViewModel

    init(viewModel: BookSiteDetailViewModel) {
        self._viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        List {
            Section {
                self.header
            }
            Section {
                if let primary: BookPublicationItem = self.viewModel.primaryChapter, self.viewModel.isAudiobook == false {
                    NavigationLink(value: LibraryBookRoute.siteChapter(self.viewModel.selection(for: self.viewModel.hasReadingProgress ? nil : primary))) {
                        Label(self.viewModel.hasReadingProgress ? "Continue Reading" : "Start Reading", systemImage: "book")
                    }
                }
            }
            Section("Chapters") {
                if self.viewModel.isLoading && self.viewModel.chapters.isEmpty {
                    ProgressView("Loading chapters…")
                } else if let message: String = self.viewModel.errorMessage, self.viewModel.chapters.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(message).foregroundStyle(.secondary)
                        Button("Retry") {
                            Task { await self.viewModel.load() }
                        }
                    }
                } else if self.viewModel.isAudiobook {
                    Text("Audiobook player is coming in a later batch.").foregroundStyle(.secondary)
                    ForEach(self.viewModel.chapters, id: \.href) { chapter in
                        Text(chapter.title)
                    }
                } else {
                    ForEach(self.viewModel.chapters, id: \.href) { chapter in
                        NavigationLink(value: LibraryBookRoute.siteChapter(self.viewModel.selection(for: chapter))) {
                            HStack {
                                Text(chapter.title).lineLimit(2)
                                if chapter.chapterURL == self.viewModel.lastReadChapterURL {
                                    Spacer()
                                    Image(systemName: "bookmark.fill").foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(self.viewModel.manifest?.title ?? self.viewModel.item.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await self.viewModel.loadIfNeeded()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: (self.viewModel.manifest?.coverURL ?? self.viewModel.item.coverURL.flatMap(URL.init(string:)))) { phase in
                if let image: Image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    ZStack {
                        Color.secondary.opacity(0.15)
                        Image(systemName: "book.closed").foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 72, height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 6) {
                Text(self.viewModel.manifest?.title ?? self.viewModel.item.title)
                    .font(.headline)
                if let author: String = self.viewModel.manifest?.author, author.isEmpty == false {
                    Text(author).font(.subheadline).foregroundStyle(.secondary)
                }
                Text(self.viewModel.source.name).font(.caption).foregroundStyle(.secondary)
                if self.viewModel.chapters.isEmpty == false {
                    Text("\(self.viewModel.chapters.count) chapters").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
