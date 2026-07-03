import Foundation
import Testing
@testable import BrowseCraft

// 中文注释：P2-3 RuleDebugger 应用层测试，覆盖只读列表调试 session 的核心边界。
struct RuleDebugUseCaseTests {
    @Test func listDebugUseCaseReturnsSuccessfulSession() async throws {
        let source: Source = try Self.source()
        let loader: RuleDebugRecordingPageContentLoader = RuleDebugRecordingPageContentLoader(
            result: .success("<html></html>")
        )
        let parser: RuleDebugRecordingRuleParser = RuleDebugRecordingRuleParser(
            items: [
                Self.item(id: "item-1", title: "First Item"),
                Self.item(id: "item-2", title: "Second Item")
            ]
        )
        let useCase: ListDebugUseCase = ListDebugUseCase(
            pageContentLoader: loader,
            ruleParser: parser,
            urlResolver: URLResolvingService(),
            now: Self.fixedDate,
            idGenerator: Self.idGenerator(prefix: "debug")
        )

        let session: RuleDebugSession = await useCase.execute(
            source: source,
            listTab: source.rule.availableListTabs.first,
            page: 2
        )

        #expect(session.status == .succeeded)
        #expect(session.input.sourceID == source.id)
        #expect(session.input.ruleID == "home-list")
        #expect(loader.requests.map(\.url.absoluteString) == ["https://example.test/home?page=2"])
        #expect(loader.requests.first?.request?.scope == .rule)
        #expect(session.requestLogs.count == 1)
        #expect(session.requestLogs.first?.requestSummary.headerCount == 1)
        #expect(session.requestLogs.first?.responseSummary?.contentLength == 13)
        #expect(parser.parsedListRuleIDs == ["home-list"])
        #expect(session.extractionLogs.first?.outputCount == 2)
        #expect(session.previewItems.map(\.title) == ["First Item", "Second Item"])
        #expect(session.issues.isEmpty)
    }

    @Test func listDebugUseCaseReturnsEmptySessionForEmptyItems() async throws {
        let source: Source = try Self.source()
        let loader: RuleDebugRecordingPageContentLoader = RuleDebugRecordingPageContentLoader(
            result: .success("<html></html>")
        )
        let parser: RuleDebugRecordingRuleParser = RuleDebugRecordingRuleParser(items: [])
        let useCase: ListDebugUseCase = ListDebugUseCase(
            pageContentLoader: loader,
            ruleParser: parser,
            urlResolver: URLResolvingService(),
            now: Self.fixedDate,
            idGenerator: Self.idGenerator(prefix: "empty")
        )

        let session: RuleDebugSession = await useCase.execute(source: source)

        #expect(session.status == .empty)
        #expect(session.previewItems.isEmpty)
        #expect(session.issues.count == 1)
        #expect(session.issues.first?.severity == .warning)
        #expect(session.issues.first?.category == .selectorEmpty)
        #expect(session.issues.first?.field == .item)
    }

    @Test func listDebugUseCaseReturnsFailedSessionForRequestError() async throws {
        let source: Source = try Self.source()
        let loader: RuleDebugRecordingPageContentLoader = RuleDebugRecordingPageContentLoader(
            result: .failure(
                URLError(.notConnectedToInternet)
            )
        )
        let parser: RuleDebugRecordingRuleParser = RuleDebugRecordingRuleParser(items: [])
        let useCase: ListDebugUseCase = ListDebugUseCase(
            pageContentLoader: loader,
            ruleParser: parser,
            urlResolver: URLResolvingService(),
            now: Self.fixedDate,
            idGenerator: Self.idGenerator(prefix: "failed")
        )

        let session: RuleDebugSession = await useCase.execute(source: source)

        #expect(session.status == .failed)
        #expect(session.requestLogs.count == 1)
        #expect(session.requestLogs.first?.errorMessage?.isEmpty == false)
        #expect(session.previewItems.isEmpty)
        #expect(session.issues.count == 1)
        #expect(session.issues.first?.severity == .error)
        #expect(session.issues.first?.category == .requestFailed)
        #expect(parser.parsedListRuleIDs.isEmpty)
    }

    private static func source() throws -> Source {
        var rule: SiteRule = try JSONDecoder().decode(
            SiteRule.self,
            from: Data(RuleJSONFixtures.completeV2SiteRule.utf8)
        )
        rule.pages?[0].request = nil
        rule.ruleSets?.listRules?[0].url = "https://example.test/home?page={page}"
        rule.ruleSets?.listRules?[0].request = RequestConfig(
            scope: .rule,
            mergePolicy: .mergeHeadersAndCookies,
            method: .get,
            headers: ["X-Debug": "1"],
            body: nil,
            cookiePolicy: .browserThenCustom,
            cookiePriority: nil,
            cookieScope: nil,
            charset: nil,
            needsWebView: nil,
            autoScroll: nil,
            imageHeaders: nil,
            imageRequest: nil
        )

        return Source(
            id: "debug-source",
            name: "Debug Source",
            baseURL: "https://example.test",
            type: .html,
            rule: rule,
            enabled: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private static func item(id: String, title: String) -> ContentItem {
        return ContentItem(
            id: id,
            sourceId: "debug-source",
            title: title,
            detailURL: "https://example.test/comics/\(id)",
            coverURL: nil,
            type: .comic,
            latestText: nil,
            updatedAt: nil
        )
    }

    private static func fixedDate() -> Date {
        return Date(timeIntervalSince1970: 3_000)
    }

    private static func idGenerator(prefix: String) -> () -> String {
        var nextID: Int = 0
        return {
            nextID += 1
            return "\(prefix)-\(nextID)"
        }
    }
}

private final class RuleDebugRecordingPageContentLoader: PageContentLoader {
    struct RecordedRequest: Hashable {
        var url: URL
        var request: RequestConfig?
    }

    private let result: Result<String, Error>
    private(set) var requests: [RecordedRequest] = []

    init(result: Result<String, Error>) {
        self.result = result
    }

    func getString(from url: URL, request: RequestConfig?) async throws -> String {
        self.requests.append(
            RecordedRequest(
                url: url,
                request: request
            )
        )

        return try self.result.get()
    }
}

private final class RuleDebugRecordingRuleParser: RuleParsingService {
    let items: [ContentItem]
    private(set) var parsedListRuleIDs: [String?] = []

    init(items: [ContentItem]) {
        self.items = items
    }

    func parseList(html: String, source: Source) throws -> [ContentItem] {
        return try self.parseList(html: html, source: source, listRule: source.rule.primaryListRule)
    }

    func parseList(html: String, source: Source, listRule: ListRule) throws -> [ContentItem] {
        self.parsedListRuleIDs.append(listRule.id)
        return self.items
    }

    func parseDetailChapters(html: String, source: Source, pageURL: String) throws -> [ChapterLink] {
        return []
    }

    func parseReader(html: String, source: Source, pageURL: String) throws -> ReaderChapter {
        return ReaderChapter(
            sourceId: source.id,
            comicTitle: nil,
            chapterTitle: nil,
            chapterURL: pageURL,
            catalogURL: nil,
            previousChapterURL: nil,
            nextChapterURL: nil,
            pageImageURLs: []
        )
    }
}
