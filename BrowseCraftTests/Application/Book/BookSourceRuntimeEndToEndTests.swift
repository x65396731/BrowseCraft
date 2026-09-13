import BrowseCraftCore
import BrowseCraftDomain
import BrowseCraftRuntime
import Foundation
import ReadiumShared
import Testing
@testable import BrowseCraft

// 中文注释：站点书从 catalog 到出版物的整链固定输入：真实 catalog → Source → BookSourceRuntime（网页由夹具桩）
// → 详情 / 章节 / 正文或音频 → manifest → Readium Publication。两站各一条。

struct BookSourceRuntimeEndToEndTests {
    @Test func biquhuaTextBookFlowsFromListToPublication() async throws {
        let loader: FixturePageContentLoader = FixturePageContentLoader(fixtures: [
            "https://www.biquhua.com/top/all_0_1.html": "biquhua-list-p1",
            "https://www.biquhua.com/book/0/110/": "biquhua-detail-110",
            "https://www.biquhua.com/book/0/110/129023.html": "biquhua-reader-110-129023",
        ])
        let source: Source = try Self.source(fixture: "biquhua-catalog")
        let runtime: BookSourceRuntime = try BookSourceRuntimeFactory(pageContentLoader: loader).makeRuntime(source: source)
        let context: SourceRuntimeContext = Self.context(sourceID: source.id)

        #expect(runtime.capabilities.supportsDetail)
        #expect(runtime.capabilities.supportsReader == false)
        #expect(runtime.capabilities.supportsPagination == false)
        #expect(runtime.capabilities.requiresAccount, "biquhua 有 loginURL")

        let list: SourceListOutput = try await runtime.loadList(SourceListInput(page: 1, urlOverride: nil, context: context))
        #expect(list.items.count == 30)
        #expect(list.pagination == nil)
        #expect(list.items.first?.itemReference?.contentType == .article)

        let detail: SourceDetailOutput = try await runtime.loadDetail(
            SourceDetailInput(detailURL: URL(string: "https://www.biquhua.com/book/0/110/")!, context: context, itemReference: nil)
        )
        #expect(detail.metadata?.title == "普罗之主")
        #expect(detail.chapters.count == 112)

        let chapterURL: URL = URL(string: "https://www.biquhua.com/book/0/110/129023.html")!
        let content: SourceBookContentOutput = try await runtime.loadBookContent(SourceBookContentInput(chapterURL: chapterURL, context: context))
        guard case .text(_, let paragraphs) = content.content else {
            Issue.record("expected text content")
            return
        }
        #expect(paragraphs.count >= 12)

        let loaded: LoadedBookPublication = try await LoadBookPublicationUseCase(runtimeResolver: SingleRuntimeResolver(runtime: runtime))
            .execute(source: source, detailURL: URL(string: "https://www.biquhua.com/book/0/110/")!)
        #expect(loaded.manifest.title == "普罗之主")
        #expect(loaded.manifest.items.count == 112)
        #expect(loaded.manifest.items.first?.href == "chapters/0001.xhtml")
        #expect(loaded.manifest.isAudiobook == false)

        let publication: Publication = ReadiumSitePublicationBuilder().build(manifest: loaded.manifest, contentProvider: loaded.contentProvider)
        #expect(publication.readingOrder.count == 112)
        #expect(publication.metadata.title == "普罗之主")
        let firstChapter: Link = try #require(publication.readingOrder.first { $0.title?.isEmpty == false })
        let index: Int = try #require(loaded.manifest.items.firstIndex { $0.chapterURL == chapterURL })
        let resource: Resource = try #require(publication.get(publication.readingOrder[index]))
        let xhtml: String = try await resource.readAsString().get()
        #expect(xhtml.contains("<p>"))
        #expect(xhtml.contains("xmlns=\"http://www.w3.org/1999/xhtml\""))
        #expect(xhtml.contains("<br") == false)
        _ = firstChapter
        #expect(loader.requestedURLs.filter { $0 == chapterURL.absoluteString }.count == 2, "运行时一次 + 出版物按需一次")
    }

    @Test func loyalbooksAudiobookFlowsToAudioPublicationWithoutFetchingMedia() async throws {
        let loader: FixturePageContentLoader = FixturePageContentLoader(fixtures: [
            "https://www.loyalbooks.com/genre/Adventure?page=1": "loyalbooks-list-adventure-p1",
            "https://www.loyalbooks.com/book/tom-sawyer-by-mark-twain": "loyalbooks-detail-tom-sawyer",
        ])
        let source: Source = try Self.source(fixture: "loyalbooks-catalog")
        let runtime: BookSourceRuntime = try BookSourceRuntimeFactory(pageContentLoader: loader).makeRuntime(source: source)
        let context: SourceRuntimeContext = Self.context(sourceID: source.id)

        #expect(runtime.capabilities.supportsPagination)
        let list: SourceListOutput = try await runtime.loadList(SourceListInput(page: 1, urlOverride: nil, context: context))
        #expect(list.items.count > 10)
        #expect(list.pagination?.nextPage == 2)
        #expect(list.pagination?.nextPageURL?.absoluteString == "https://www.loyalbooks.com/genre/Adventure?page=2")

        let detailURL: URL = URL(string: "https://www.loyalbooks.com/book/tom-sawyer-by-mark-twain")!
        let detail: SourceDetailOutput = try await runtime.loadDetail(SourceDetailInput(detailURL: detailURL, context: context, itemReference: nil))
        #expect(detail.chapters.count == 17)

        let firstChapter: URL = try #require(detail.chapters.first?.url)
        let content: SourceBookContentOutput = try await runtime.loadBookContent(SourceBookContentInput(chapterURL: firstChapter, context: context))
        guard case .audio(let items) = content.content else {
            Issue.record("expected audio content")
            return
        }
        #expect(items.count == 1)
        #expect(items.first?.url == firstChapter)
        #expect(items.first?.mediaType == "audio/mpeg")
        #expect(loader.requestedURLs.contains(firstChapter.absoluteString) == false, "BC-BOOK-051：mp3 出边不再取页")

        let loaded: LoadedBookPublication = try await LoadBookPublicationUseCase(runtimeResolver: SingleRuntimeResolver(runtime: runtime))
            .execute(source: source, detailURL: detailURL)
        #expect(loaded.manifest.isAudiobook)
        #expect(loaded.manifest.items.allSatisfy { $0.href.hasSuffix(".mp3") })
        let publication: Publication = ReadiumSitePublicationBuilder().build(manifest: loaded.manifest, contentProvider: loaded.contentProvider)
        #expect(publication.readingOrder.count == 17)
        #expect(publication.readingOrder.first?.mediaType?.isAudio == true)
        #expect(publication.metadata.conformsTo.contains(.audiobook))
    }

    @Test func xhtmlRendererEscapesAndSkipsEmptyParagraphs() {
        let xhtml: String = BookXHTMLRenderer().render(title: "A <b> & \"c\"", paragraphs: ["one", "", "<two>"], language: "zh-Hans")
        #expect(xhtml.contains("<h1>A &lt;b&gt; &amp; &quot;c&quot;</h1>"))
        #expect(xhtml.contains("<p>one</p>"))
        #expect(xhtml.contains("<p>&lt;two&gt;</p>"))
        #expect(xhtml.contains("<p></p>") == false)
        #expect(xhtml.contains("xml:lang=\"zh-Hans\""))
    }

    // MARK: - Helpers

    private static func source(fixture: String) throws -> Source {
        let url: URL = try #require(Bundle(for: BookRuntimeFixtureMarker.self).url(forResource: fixture, withExtension: "json"))
        let catalog: [String: Any] = try #require(JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        let ruleJSON: Data = try JSONSerialization.data(withJSONObject: try #require(catalog["ruleJSON"]))
        let catalogSource: CatalogSource = CatalogSource(
            id: try #require(catalog["id"] as? String),
            name: try #require(catalog["name"] as? String),
            baseURL: try #require(catalog["baseURL"] as? String),
            kind: .book,
            ruleJSON: String(decoding: ruleJSON, as: UTF8.self)
        )
        return try CatalogSourceMaterializer().source(from: catalogSource, createdAt: Date(), updatedAt: Date())
    }

    private static func context(sourceID: String) -> SourceRuntimeContext {
        return SourceRuntimeContext(sourceID: sourceID, pageID: nil, tabID: nil, ruleID: nil, requestOverride: nil, debugMode: false)
    }
}

private final class BookRuntimeFixtureMarker {}

private struct SingleRuntimeResolver: SourceRuntimeResolving {
    let runtime: BookSourceRuntime
    func runtime(for source: Source) throws -> any SourceRuntime {
        return self.runtime
    }
}

/// 中文注释：按 URL 回夹具 HTML；没备的 URL 直接报错，避免测试静默走到网络。
private final class FixturePageContentLoader: PageContentLoader, @unchecked Sendable {
    private let fixtures: [String: String]
    private(set) var requestedURLs: [String] = []
    private let lock: NSLock = NSLock()

    init(fixtures: [String: String]) {
        self.fixtures = fixtures
    }

    func loadContent(_ request: PageLoadRequest) async throws -> PageContentResponse {
        self.lock.lock()
        self.requestedURLs.append(request.url.absoluteString)
        self.lock.unlock()
        guard let name: String = self.fixtures[request.url.absoluteString],
              let url: URL = Bundle(for: BookRuntimeFixtureMarker.self).url(forResource: name, withExtension: "html") else {
            throw NSError(domain: "FixturePageContentLoader", code: 404, userInfo: [NSLocalizedDescriptionKey: "no fixture for \(request.url)"])
        }
        return PageContentResponse(content: try String(contentsOf: url, encoding: .utf8), finalURL: request.url)
    }
}
