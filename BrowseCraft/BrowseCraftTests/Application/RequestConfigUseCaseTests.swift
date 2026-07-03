import Foundation
import Testing
@testable import BrowseCraft

// 中文注释：应用层请求配置测试，确认 P1-4.1 已把 V2 RequestConfig 从规则模型传到网络请求入口。
struct RequestConfigUseCaseTests {
    @Test func refreshSourcePassesListRequestToHTTPClient() async throws {
        let source: Source = try Self.source()
        let httpClient: RecordingHTTPClient = RecordingHTTPClient(html: "<html></html>")
        let ruleParser: RecordingRuleParser = RecordingRuleParser()
        let contentRepository: InMemoryContentRepository = InMemoryContentRepository()
        let useCase: RefreshSourceUseCase = RefreshSourceUseCase(
            httpClient: httpClient,
            ruleParser: ruleParser,
            urlResolver: URLResolvingService(),
            contentRepository: contentRepository
        )

        _ = try await useCase.execute(source: source, listTab: source.rule.availableListTabs.first)

        // 中文注释：列表页拥有 PageRule.request 和 ListRule.request 时，当前阶段应选择更具体的规则级 request。
        #expect(httpClient.requests.first?.request?.scope == .rule)
        #expect(httpClient.requests.first?.request?.mergePolicy == .mergeHeadersAndCookies)
        #expect(ruleParser.parsedListRuleIDs == ["home-list"])
        // 中文注释：P1-5.1 列表刷新要把 Page/Tab/ListRule 上下文保存到 item，供后续详情解析缩小范围。
        #expect(contentRepository.items.first?.listContext?.pageId == "home")
        #expect(contentRepository.items.first?.listContext?.tabId == "discover")
        #expect(contentRepository.items.first?.listContext?.listRuleId == "home-list")
        #expect(contentRepository.items.first?.listContext?.sectionRole == .main)
    }

    @Test func loadChaptersPassesDetailRequestToHTTPClient() async throws {
        var source: Source = try Self.source()
        source.rule.pages?[1].request = RequestConfig(
            scope: .page,
            mergePolicy: .mergeHeaders,
            method: .get,
            headers: ["X-Detail-Page": "1"],
            body: nil,
            cookiePolicy: nil,
            cookiePriority: nil,
            cookieScope: nil,
            charset: nil,
            needsWebView: nil,
            autoScroll: nil,
            imageHeaders: nil,
            imageRequest: nil
        )

        let httpClient: RecordingHTTPClient = RecordingHTTPClient(html: "<html></html>")
        let ruleParser: RecordingRuleParser = RecordingRuleParser()
        let useCase: LoadChaptersUseCase = LoadChaptersUseCase(
            httpClient: httpClient,
            ruleParser: ruleParser
        )

        _ = try await useCase.execute(source: source, item: Self.item())

        // 中文注释：详情页章节加载要使用 detail PageRule.request，避免和列表页、阅读页请求头混用。
        #expect(httpClient.requests.first?.request?.scope == .page)
        #expect(httpClient.requests.first?.request?.headers?["X-Detail-Page"] == "1")
        #expect(ruleParser.parsedDetailPageURLs == ["https://example.test/comics/100"])
        // 中文注释：P1-5.3 详情解析必须收到列表来源上下文，才能按来源 section 缩小章节作用域。
        #expect(ruleParser.parsedDetailContexts.first.flatMap { $0 }?.sectionId == "main-grid")
    }

    @Test func loadReaderPassesGalleryRequestToHTTPClient() async throws {
        let source: Source = try Self.source()
        let httpClient: RecordingHTTPClient = RecordingHTTPClient(html: "<html></html>")
        let ruleParser: RecordingRuleParser = RecordingRuleParser()
        let useCase: LoadReaderChapterUseCase = LoadReaderChapterUseCase(
            httpClient: httpClient,
            ruleParser: ruleParser
        )

        _ = try await useCase.execute(
            source: source,
            item: Self.item(),
            chapterURLString: "https://example.test/chapters/100-1"
        )

        // 中文注释：阅读页 HTML 抓取应选择 gallery rule request，为后续图片 referer 和 WebView 标记接线保留入口。
        #expect(httpClient.requests.first?.request?.scope == .image)
        #expect(httpClient.requests.first?.request?.imageRequest?.headers?["Referer"] == "https://example.test/reader")
        #expect(ruleParser.parsedReaderPageURLs == ["https://example.test/chapters/100-1"])
        // 中文注释：P1-5.3 阅读页解析必须收到列表来源上下文，避免推荐区图片混入正文。
        #expect(ruleParser.parsedReaderContexts.first.flatMap { $0 }?.sectionId == "main-grid")
    }

    private static func source() throws -> Source {
        let rule: SiteRule = try JSONDecoder().decode(
            SiteRule.self,
            from: Data(RuleJSONFixtures.completeV2SiteRule.utf8)
        )

        return Source(
            id: "v2-request-source",
            name: "V2 Request Source",
            baseURL: "https://example.test",
            type: .html,
            rule: rule,
            enabled: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private static func item() -> ContentItem {
        return ContentItem(
            id: "item-100",
            sourceId: "v2-request-source",
            title: "Request Item",
            detailURL: "https://example.test/comics/100",
            coverURL: nil,
            type: .comic,
            latestText: nil,
            updatedAt: nil,
            listContext: ListContext(
                pageId: "home",
                tabId: "home",
                sectionId: "main-grid",
                listRuleId: "home-list",
                sectionRole: .main
            )
        )
    }
}

private final class RecordingHTTPClient: HTTPClient {
    struct RecordedRequest: Hashable {
        var url: URL
        var request: RequestConfig?
    }

    private let html: String
    private(set) var requests: [RecordedRequest] = []

    init(html: String) {
        self.html = html
    }

    func getString(from url: URL, request: RequestConfig?) async throws -> String {
        self.requests.append(
            RecordedRequest(
                url: url,
                request: request
            )
        )

        return self.html
    }
}

private final class RecordingRuleParser: RuleParsingService {
    private(set) var parsedListRuleIDs: [String?] = []
    private(set) var parsedDetailPageURLs: [String] = []
    private(set) var parsedDetailContexts: [ListContext?] = []
    private(set) var parsedReaderPageURLs: [String] = []
    private(set) var parsedReaderContexts: [ListContext?] = []

    func parseList(html: String, source: Source) throws -> [ContentItem] {
        return try self.parseList(
            html: html,
            source: source,
            listRule: source.rule.primaryListRule
        )
    }

    func parseList(html: String, source: Source, listRule: ListRule) throws -> [ContentItem] {
        self.parsedListRuleIDs.append(listRule.id)

        return [
            ContentItem(
                id: "item-100",
                sourceId: source.id,
                title: "Request Item",
                detailURL: "https://example.test/comics/100",
                coverURL: nil,
                type: .comic,
                latestText: nil,
                updatedAt: nil
            )
        ]
    }

    func parseDetailChapters(html: String, source: Source, pageURL: String) throws -> [ChapterLink] {
        self.parsedDetailPageURLs.append(pageURL)

        return [
            ChapterLink(
                title: "第01话",
                url: "https://example.test/chapters/100-1"
            )
        ]
    }

    func parseDetailChapters(
        html: String,
        source: Source,
        pageURL: String,
        context: ListContext?
    ) throws -> [ChapterLink] {
        self.parsedDetailContexts.append(context)

        return try self.parseDetailChapters(
            html: html,
            source: source,
            pageURL: pageURL
        )
    }

    func parseReader(html: String, source: Source, pageURL: String) throws -> ReaderChapter {
        self.parsedReaderPageURLs.append(pageURL)

        return ReaderChapter(
            sourceId: source.id,
            comicTitle: "Request Item",
            chapterTitle: "第01话",
            chapterURL: pageURL,
            catalogURL: nil,
            previousChapterURL: nil,
            nextChapterURL: nil,
            pageImageURLs: ["https://example.test/images/1.jpg"]
        )
    }

    func parseReader(
        html: String,
        source: Source,
        pageURL: String,
        context: ListContext?
    ) throws -> ReaderChapter {
        self.parsedReaderContexts.append(context)

        return try self.parseReader(
            html: html,
            source: source,
            pageURL: pageURL
        )
    }
}

private final class InMemoryContentRepository: ContentRepository {
    private(set) var items: [ContentItem] = []

    func fetchItems() throws -> [ContentItem] {
        return self.items
    }

    func fetchItems(sourceId: String?) throws -> [ContentItem] {
        guard let sourceId: String = sourceId else {
            return self.items
        }

        return self.items.filter { item in
            return item.sourceId == sourceId
        }
    }

    func saveItems(_ items: [ContentItem]) throws {
        self.items = items
    }
}
