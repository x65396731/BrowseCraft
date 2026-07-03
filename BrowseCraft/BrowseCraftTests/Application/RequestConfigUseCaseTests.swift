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

    @Test func loadChaptersTreatsDetailURLAsSingleChapterWhenRuleRequestsIt() async throws {
        let source: Source = try Self.oneLayerReaderSource()
        let httpClient: RecordingHTTPClient = RecordingHTTPClient(html: "<html></html>")
        let ruleParser: RecordingRuleParser = RecordingRuleParser()
        let useCase: LoadChaptersUseCase = LoadChaptersUseCase(
            httpClient: httpClient,
            ruleParser: ruleParser
        )
        let item: ContentItem = Self.oneLayerReaderItem()

        let chapters: [ChapterLink] = try await useCase.execute(source: source, item: item)

        // 中文注释：Pepper&Carrot 这类一层源的列表项已经是阅读页，章节目录应直接由 detailURL 构成，不能再请求详情页。
        #expect(chapters == [
            ChapterLink(
                title: "第17集：新的开始",
                url: "https://www.peppercarrot.com/cn/webcomic/ep17_A-Fresh-Start.html"
            )
        ])
        #expect(httpClient.requests.isEmpty)
        #expect(ruleParser.parsedDetailPageURLs.isEmpty)
    }

    @Test func loadReaderTreatsDetailURLAsChapterAndSkipsDetailParsingWhenRuleRequestsIt() async throws {
        let source: Source = try Self.oneLayerReaderSource()
        let httpClient: RecordingHTTPClient = RecordingHTTPClient(html: "<html></html>")
        let ruleParser: RecordingRuleParser = RecordingRuleParser()
        let useCase: LoadReaderChapterUseCase = LoadReaderChapterUseCase(
            httpClient: httpClient,
            ruleParser: ruleParser
        )
        let item: ContentItem = Self.oneLayerReaderItem()

        let chapter: ReaderChapter = try await useCase.execute(source: source, item: item)

        // 中文注释：未指定 preferredChapterURL 时，一层源 reader 应直接请求 item.detailURL，避免退回二层详情页章节抽取。
        #expect(httpClient.requests.map(\.url.absoluteString) == [
            "https://www.peppercarrot.com/cn/webcomic/ep17_A-Fresh-Start.html"
        ])
        #expect(httpClient.requests.first?.request?.scope == .image)
        #expect(ruleParser.parsedDetailPageURLs.isEmpty)
        #expect(ruleParser.parsedReaderPageURLs == [
            "https://www.peppercarrot.com/cn/webcomic/ep17_A-Fresh-Start.html"
        ])
        #expect(chapter.pageImageURLs == ["https://example.test/images/1.jpg"])
    }

    @Test func refreshSourceReplacesOnlySelectedTabCache() async throws {
        let source: Source = try Self.source()
        let tabs: [ListTabRule] = source.rule.availableListTabs
        let discoverTab: ListTabRule = try #require(tabs.first { tab in tab.id == "discover" })
        let latestTab: ListTabRule = try #require(tabs.first { tab in tab.id == "latest" })
        let contentRepository: InMemoryContentRepository = InMemoryContentRepository()
        contentRepository.seed([
            Self.cachedItem(id: "discover-old", sourceID: source.id, tab: discoverTab),
            Self.cachedItem(id: "latest-old", sourceID: source.id, tab: latestTab)
        ])

        let ruleParser: RecordingRuleParser = RecordingRuleParser()
        ruleParser.listItemsByRuleID = [
            "home-list": [
                Self.cachedItem(id: "discover-new", sourceID: source.id, tab: discoverTab)
            ]
        ]
        let refreshUseCase: RefreshSourceUseCase = RefreshSourceUseCase(
            httpClient: RecordingHTTPClient(html: "<html></html>"),
            ruleParser: ruleParser,
            urlResolver: URLResolvingService(),
            contentRepository: contentRepository
        )
        let loadLibraryUseCase: LoadLibraryUseCase = LoadLibraryUseCase(
            contentRepository: contentRepository
        )

        _ = try await refreshUseCase.execute(source: source, listTab: discoverTab)

        let discoverItems: [ContentItem] = try loadLibraryUseCase.execute(
            sourceId: source.id,
            listTab: discoverTab
        )
        let latestItems: [ContentItem] = try loadLibraryUseCase.execute(
            sourceId: source.id,
            listTab: latestTab
        )

        // 中文注释：P1-7.3 的缓存边界是 source + tab + listRule；刷新 discover 不能删掉 latest 的缓存。
        #expect(discoverItems.map(\.id) == ["discover-new"])
        #expect(latestItems.map(\.id) == ["latest-old"])
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

    private static func oneLayerReaderSource() throws -> Source {
        var source: Source = try Self.source()
        source.id = "peppercarrot-one-layer-source"
        source.name = "Pepper&Carrot One Layer Source"
        source.baseURL = "https://www.peppercarrot.com/cn"
        source.rule.ruleSets?.detailRules?[0].treatDetailURLAsChapter = true
        return source
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

    private static func oneLayerReaderItem() -> ContentItem {
        var item: ContentItem = Self.item()
        item.id = "peppercarrot-ep17"
        item.sourceId = "peppercarrot-one-layer-source"
        item.title = "第17集：新的开始"
        item.detailURL = "https://www.peppercarrot.com/cn/webcomic/ep17_A-Fresh-Start.html"
        item.latestText = "第17集：新的开始"
        return item
    }

    private static func cachedItem(id: String, sourceID: String, tab: ListTabRule) -> ContentItem {
        return ContentItem(
            id: id,
            sourceId: sourceID,
            title: id,
            detailURL: "https://example.test/comics/\(id)",
            coverURL: nil,
            type: .comic,
            latestText: nil,
            updatedAt: Date(timeIntervalSince1970: 0),
            listContext: Self.listContext(tab: tab)
        )
    }

    private static func listContext(tab: ListTabRule) -> ListContext {
        if var context: ListContext = tab.context {
            if context.listRuleId == nil {
                context.listRuleId = tab.list.id
            }

            return context
        }

        return ListContext(
            pageId: tab.id,
            tabId: tab.id,
            sectionId: nil,
            listRuleId: tab.list.id,
            sectionRole: .main
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
    var listItemsByRuleID: [String: [ContentItem]] = [:]
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

        if let listRuleID: String = listRule.id,
           let items: [ContentItem] = self.listItemsByRuleID[listRuleID] {
            return items
        }

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

    func seed(_ items: [ContentItem]) {
        self.items = items
    }

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

    func fetchItems(sourceId: String?, context: ListContext?) throws -> [ContentItem] {
        let sourceItems: [ContentItem] = try self.fetchItems(sourceId: sourceId)
        guard let context: ListContext = context else {
            return sourceItems
        }

        return sourceItems.filter { item in
            return self.matches(item: item, context: context)
        }
    }

    func saveItems(_ items: [ContentItem]) throws {
        self.items = items
    }

    func replaceItems(_ items: [ContentItem], sourceId: String, context: ListContext?) throws {
        self.items.removeAll { item in
            guard item.sourceId == sourceId else {
                return false
            }

            guard let context: ListContext = context else {
                return true
            }

            return self.matches(item: item, context: context)
        }
        self.items.append(contentsOf: items)
    }

    private func matches(item: ContentItem, context: ListContext) -> Bool {
        if let tabId: String = context.tabId,
           item.listContext?.tabId != tabId {
            return false
        }

        if let listRuleId: String = context.listRuleId,
           item.listContext?.listRuleId != listRuleId {
            return false
        }

        return true
    }
}
