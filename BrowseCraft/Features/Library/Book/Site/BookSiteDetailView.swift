import BrowseCraftDomain
import SwiftUI

// 中文注释：BookSiteDetailView：站点作品的详情页——头部、开始 / 继续阅读、章节列表；章节推入共用的 EPUB 阅读器。
// 章节用本视图自己的 navigationDestination(item:) 推入（与 ComicDetailView 同款），不能用 NavigationLink(value:)
// 走栈根的 LibraryBookRoute：详情本身是 item 式推入的，两种推入混用时栈序会变成「库 → 阅读器 → 详情」
// （2026-09-14 模拟器实测，见 Documentation/Book/Book-Kind-Wiring-Design.md 第十二节）。

struct BookSiteDetailView: View {
    @State private var viewModel: BookSiteDetailViewModel
    @State private var selectedChapter: SiteBookChapterSelection?
    private let makeReaderViewModel: @MainActor (SiteBookChapterSelection) -> BookReaderViewModel

    init(
        viewModel: BookSiteDetailViewModel,
        makeReaderViewModel: @escaping @MainActor (SiteBookChapterSelection) -> BookReaderViewModel
    ) {
        self._viewModel = State(wrappedValue: viewModel)
        self.makeReaderViewModel = makeReaderViewModel
    }

    var body: some View {
        List {
            Section {
                self.header
            }
            Section {
                if let primary: BookPublicationItem = self.viewModel.primaryChapter {
                    Button {
                        self.selectedChapter = self.viewModel.selection(for: self.viewModel.hasReadingProgress ? nil : primary)
                    } label: {
                        self.chevronRow {
                            if self.viewModel.isAudiobook {
                                Label(self.viewModel.hasReadingProgress ? "Continue Listening" : "Start Listening", systemImage: "headphones")
                            } else {
                                Label(self.viewModel.hasReadingProgress ? "Continue Reading" : "Start Reading", systemImage: "book")
                            }
                        }
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
                } else {
                    ForEach(self.viewModel.chapters, id: \.href) { chapter in
                        Button {
                            self.selectedChapter = self.viewModel.selection(for: chapter)
                        } label: {
                            self.chevronRow {
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
        .navigationDestination(item: self.$selectedChapter) { selection in
            BookReaderView(viewModel: self.makeReaderViewModel(selection))
                .id(selection)
        }
    }

    /// 中文注释：Button 行没有 NavigationLink 自带的箭头，手动补一个，保持与系统列表一致的观感。
    private func chevronRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack {
            content()
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        // 中文注释：List 里的 Button 会把标签染成 tint 色；用 Color.primary（而不是 .primary 层级样式）压回正文色。
        .foregroundStyle(Color.primary)
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
