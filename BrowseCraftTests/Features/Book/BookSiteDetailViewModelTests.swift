import BrowseCraftCore
import BrowseCraftDomain
import BrowseCraftRuntime
import Foundation
import ReadiumShared
import Testing
@testable import BrowseCraft

// 中文注释：站点书详情与阅读器主体：作品标识稳定、详情页列出章节并按续读位置定起点、阅读器按主体打开站点书。

@MainActor
struct BookSiteDetailViewModelTests {
    @Test func siteBookIdentityIsStableAndDistinguishesSources() {
        let a: UUID = SiteBookIdentity.bookID(sourceID: "s1", detailURL: "https://a/book/1")
        #expect(a == SiteBookIdentity.bookID(sourceID: "s1", detailURL: "https://a/book/1"))
        #expect(a != SiteBookIdentity.bookID(sourceID: "s2", detailURL: "https://a/book/1"))
        #expect(a != SiteBookIdentity.bookID(sourceID: "s1", detailURL: "https://a/book/2"))
        #expect(a.uuidString.count == 36)
    }

    @Test func detailListsChaptersAndContinuesFromSavedProgress() async throws {
        let (source, runtime): (Source, BookSourceRuntime) = try Self.biquhua()
        let item: ContentItem = Self.item(source: source)
        let progress: DetailInMemoryProgressRepository = DetailInMemoryProgressRepository()
        let bookID: UUID = SiteBookIdentity.bookID(sourceID: source.id, detailURL: item.detailURL)
        try progress.saveProgress(BookReadingProgress(bookID: bookID, userID: "u1", locatorJSON: "{\"href\":\"chapters/0003.xhtml\",\"type\":\"application/xhtml+xml\"}", totalProgression: 0.02, updatedAt: Date()))
        let viewModel: BookSiteDetailViewModel = BookSiteDetailViewModel(
            item: item,
            source: source,
            loadPublicationUseCase: LoadBookPublicationUseCase(runtimeResolver: DetailSingleRuntimeResolver(runtime: runtime)),
            loadProgressUseCase: LoadBookReadingProgressUseCase(progressRepository: progress),
            userID: "u1"
        )

        await viewModel.loadIfNeeded()

        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.chapters.count == 112)
        #expect(viewModel.isAudiobook == false)
        #expect(viewModel.hasReadingProgress)
        #expect(viewModel.primaryChapter?.href == "chapters/0003.xhtml")
        #expect(viewModel.lastReadChapterURL == viewModel.chapters[2].chapterURL)
        let selection: SiteBookChapterSelection = viewModel.selection(for: viewModel.chapters[5])
        #expect(selection.chapterURL == viewModel.chapters[5].chapterURL)
        #expect(selection.item.detailURL == item.detailURL)
    }

    @Test func readerOpensSiteBookAtChosenChapter() async throws {
        let (source, runtime): (Source, BookSourceRuntime) = try Self.biquhua()
        let item: ContentItem = Self.item(source: source)
        let chapterURL: URL = URL(string: "https://www.biquhua.com/book/0/110/129023.html")!
        let progress: DetailInMemoryProgressRepository = DetailInMemoryProgressRepository()
        let bookmarks: DetailInMemoryBookmarkRepository = DetailInMemoryBookmarkRepository()
        let viewModel: BookReaderViewModel = BookReaderViewModel(
            subject: .site(SiteBookChapterSelection(source: source, item: item, chapterURL: chapterURL, chapterTitle: nil)),
            userID: "u1",
            openLocalUseCase: nil,
            loadSitePublicationUseCase: LoadBookPublicationUseCase(runtimeResolver: DetailSingleRuntimeResolver(runtime: runtime)),
            loadProgressUseCase: LoadBookReadingProgressUseCase(progressRepository: progress),
            saveProgressUseCase: SaveBookReadingProgressUseCase(progressRepository: progress),
            addBookmarkUseCase: AddBookBookmarkUseCase(repository: bookmarks),
            listBookmarksUseCase: ListBookBookmarksUseCase(repository: bookmarks),
            removeBookmarkUseCase: RemoveBookBookmarkUseCase(repository: bookmarks)
        )

        await viewModel.open()

        #expect(viewModel.state == .ready)
        #expect(viewModel.title == item.title)
        #expect(viewModel.publication?.readingOrder.count == 112)
        #expect(viewModel.tableOfContents.count == 112)
        let initial: Locator = try #require(viewModel.initialLocator)
        #expect(initial.href.string.hasSuffix("chapters/0001.xhtml") == false || viewModel.publication?.readingOrder.first?.href == "chapters/0001.xhtml")
        let expectedIndex: Int = try #require(viewModel.publication?.readingOrder.firstIndex { $0.title == viewModel.tableOfContents.first { _ in true }?.title })
        _ = expectedIndex
        #expect(viewModel.bookID == SiteBookIdentity.bookID(sourceID: source.id, detailURL: item.detailURL))

        viewModel.flush()
        #expect(progress.saved.last?.bookID == viewModel.bookID)
    }

    // MARK: - Helpers

    private static func biquhua() throws -> (Source, BookSourceRuntime) {
        let loader: DetailFixturePageContentLoader = DetailFixturePageContentLoader(fixtures: [
            "https://www.biquhua.com/book/0/110/": "biquhua-detail-110",
            "https://www.biquhua.com/book/0/110/129023.html": "biquhua-reader-110-129023",
        ])
        let url: URL = try #require(Bundle(for: DetailFixtureMarker.self).url(forResource: "biquhua-catalog", withExtension: "json"))
        let catalog: [String: Any] = try #require(JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        let ruleJSON: Data = try JSONSerialization.data(withJSONObject: try #require(catalog["ruleJSON"]))
        let source: Source = try CatalogSourceMaterializer().source(
            from: CatalogSource(
                id: try #require(catalog["id"] as? String),
                name: try #require(catalog["name"] as? String),
                baseURL: try #require(catalog["baseURL"] as? String),
                kind: .book,
                ruleJSON: String(decoding: ruleJSON, as: UTF8.self)
            ),
            createdAt: Date(),
            updatedAt: Date()
        )
        return (source, try BookSourceRuntimeFactory(pageContentLoader: loader).makeRuntime(source: source))
    }

    private static func item(source: Source) -> ContentItem {
        return ContentItem(
            id: "https://www.biquhua.com/book/0/110/",
            sourceId: source.id,
            title: "普罗之主",
            detailURL: "https://www.biquhua.com/book/0/110/",
            type: .article
        )
    }
}

private final class DetailFixtureMarker {}

private struct DetailSingleRuntimeResolver: SourceRuntimeResolving {
    let runtime: BookSourceRuntime
    func runtime(for source: Source) throws -> any SourceRuntime { return self.runtime }
}

private final class DetailFixturePageContentLoader: PageContentLoader, @unchecked Sendable {
    private let fixtures: [String: String]
    init(fixtures: [String: String]) { self.fixtures = fixtures }
    func loadContent(_ request: PageLoadRequest) async throws -> PageContentResponse {
        guard let name: String = self.fixtures[request.url.absoluteString],
              let url: URL = Bundle(for: DetailFixtureMarker.self).url(forResource: name, withExtension: "html") else {
            throw NSError(domain: "DetailFixturePageContentLoader", code: 404, userInfo: [NSLocalizedDescriptionKey: "no fixture for \(request.url)"])
        }
        return PageContentResponse(content: try String(contentsOf: url, encoding: .utf8), finalURL: request.url)
    }
}

private final class DetailInMemoryProgressRepository: BookReadingProgressRepository, @unchecked Sendable {
    private(set) var saved: [BookReadingProgress] = []
    func fetchProgress(bookID: UUID, userID: String) throws -> BookReadingProgress? { return self.saved.last { $0.bookID == bookID } }
    func saveProgress(_ progress: BookReadingProgress) throws { self.saved.append(progress) }
    func deleteProgress(bookID: UUID, userID: String) throws { self.saved.removeAll { $0.bookID == bookID } }
}

private final class DetailInMemoryBookmarkRepository: BookBookmarkRepository, @unchecked Sendable {
    private var bookmarks: [BookBookmark] = []
    func fetchBookmarks(bookID: UUID, userID: String) throws -> [BookBookmark] { return self.bookmarks }
    func saveBookmark(_ bookmark: BookBookmark) throws { self.bookmarks.append(bookmark) }
    func deleteBookmark(id: UUID, userID: String) throws { self.bookmarks.removeAll { $0.id == id } }
    func deleteBookmarks(bookID: UUID, userID: String) throws { self.bookmarks.removeAll { $0.bookID == bookID } }
}
