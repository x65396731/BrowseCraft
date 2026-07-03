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

        try await Self.assertSearchDebugUseCaseReturnsSuccessfulSession()
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

    @Test func listDebugUseCaseAttachesCandidateReport() async throws {
        let source: Source = try Self.source()
        let loader: RuleDebugRecordingPageContentLoader = RuleDebugRecordingPageContentLoader(
            result: .success("<main><article class=\"card\"><a href=\"/one\">One</a></article><a class=\"next\" href=\"/home?page=2\">Next</a></main>")
        )
        let parser: RuleDebugRecordingRuleParser = RuleDebugRecordingRuleParser(
            items: [
                Self.item(id: "item-1", title: "First Item")
            ]
        )
        let candidateAnalyzer: RuleDebugRecordingCandidateAnalyzer = RuleDebugRecordingCandidateAnalyzer()
        let useCase: ListDebugUseCase = ListDebugUseCase(
            pageContentLoader: loader,
            ruleParser: parser,
            urlResolver: URLResolvingService(),
            candidateAnalyzer: candidateAnalyzer,
            now: Self.fixedDate,
            idGenerator: Self.idGenerator(prefix: "candidate-debug")
        )

        let session: RuleDebugSession = await useCase.execute(
            source: source,
            listTab: source.rule.availableListTabs.first,
            page: 1
        )

        let candidateReport: RuleCandidateReport = try #require(session.candidateReport)
        #expect(candidateAnalyzer.listInputs.map(\.ruleID) == ["home-list"])
        #expect(candidateAnalyzer.paginationInputs.map(\.stage) == [.list])
        #expect(candidateAnalyzer.paginationInputs.map(\.urlTemplate) == ["https://example.test/home?page={page}"])
        #expect(candidateReport.stage == .list)
        #expect(candidateReport.candidates.map(\.field) == [.item, .nextPage])
        #expect(candidateReport.summary.candidateCount == 2)
        #expect(candidateReport.summary.coveredFields.contains(.item))
        #expect(candidateReport.summary.coveredFields.contains(.nextPage))
        #expect(session.issues.isEmpty)
    }

    @Test func searchDebugUseCaseAttachesCandidateReport() async throws {
        let source: Source = try Self.searchSource()
        let loader: RuleDebugRecordingPageContentLoader = RuleDebugRecordingPageContentLoader(
            result: .success("<main><article class=\"card\"><a href=\"/search-1\">One</a></article><a class=\"next\" href=\"/search?q=cat&page=2\">Next</a></main>")
        )
        let parser: RuleDebugRecordingRuleParser = RuleDebugRecordingRuleParser(
            items: [
                Self.item(id: "search-1", title: "Search First")
            ]
        )
        let candidateAnalyzer: RuleDebugRecordingCandidateAnalyzer = RuleDebugRecordingCandidateAnalyzer()
        let useCase: SearchDebugUseCase = SearchDebugUseCase(
            pageContentLoader: loader,
            ruleParser: parser,
            urlResolver: URLResolvingService(),
            candidateAnalyzer: candidateAnalyzer,
            now: Self.fixedDate,
            idGenerator: Self.idGenerator(prefix: "search-candidate-debug")
        )

        let session: RuleDebugSession = await useCase.execute(
            source: source,
            keyword: "cat",
            page: 1
        )

        let candidateReport: RuleCandidateReport = try #require(session.candidateReport)
        #expect(candidateAnalyzer.listInputs.map(\.ruleID) == ["home-list"])
        #expect(candidateAnalyzer.paginationInputs.map(\.stage) == [.search])
        #expect(candidateAnalyzer.paginationInputs.map(\.ruleID) == ["search"])
        #expect(candidateAnalyzer.paginationInputs.map(\.urlTemplate) == ["/search?q={keyword:}&page={page}"])
        #expect(candidateReport.stage == .search)
        #expect(candidateReport.candidates.map(\.field) == [.item, .nextPage])
        #expect(candidateReport.summary.candidateCount == 2)
        #expect(session.issues.isEmpty)
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

    private static func searchSource() throws -> Source {
        var source: Source = try Self.source()
        source.rule.urlPatterns?.searchTemplate = nil
        source.rule.pages?.append(
            PageRule(
                id: "search",
                title: "Search",
                type: .search,
                url: nil,
                displayMode: nil,
                request: RequestConfig(
                    scope: .page,
                    mergePolicy: .mergeHeaders,
                    method: .get,
                    headers: ["X-Search-Page": "1"],
                    body: nil,
                    cookiePolicy: nil,
                    cookiePriority: nil,
                    cookieScope: nil,
                    charset: nil,
                    needsWebView: nil,
                    autoScroll: nil,
                    imageHeaders: nil,
                    imageRequest: nil
                ),
                tabGroup: nil,
                sections: nil,
                ruleRefs: RuleRefs(
                    series: nil,
                    list: nil,
                    detail: nil,
                    gallery: nil,
                    search: "search"
                ),
                flags: nil
            )
        )
        source.rule.ruleSets?.searchRules?[0].url = "/search?q={keyword:}&page={page}"
        source.rule.ruleSets?.searchRules?[0].request = RequestConfig(
            scope: .search,
            mergePolicy: .override,
            method: .get,
            headers: ["X-Search-Rule": "1"],
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
        source.rule.ruleSets?.searchRules?[0].pagination = PaginationRule(
            nextPage: nil,
            pagePlaceholder: "{page}",
            maxPages: 4,
            stopWhenEmpty: true
        )
        return source
    }

    private static func assertSearchDebugUseCaseReturnsSuccessfulSession() async throws {
        let source: Source = try Self.searchSource()
        let loader: RuleDebugRecordingPageContentLoader = RuleDebugRecordingPageContentLoader(
            result: .success("<html></html>")
        )
        let parser: RuleDebugRecordingRuleParser = RuleDebugRecordingRuleParser(
            items: [
                Self.item(id: "search-1", title: "Search First")
            ]
        )
        parser.nextPageURL = "/search?q=%E7%8C%AB&page=3"
        let useCase: SearchDebugUseCase = SearchDebugUseCase(
            pageContentLoader: loader,
            ruleParser: parser,
            urlResolver: URLResolvingService(),
            now: Self.fixedDate,
            idGenerator: Self.idGenerator(prefix: "search-debug")
        )

        let session: RuleDebugSession = await useCase.execute(
            source: source,
            keyword: "猫",
            page: 2
        )

        #expect(session.status == .succeeded)
        #expect(session.input.stage == .search)
        #expect(session.input.pageID == "search")
        #expect(session.input.ruleID == "search")
        #expect(session.input.keyword == "猫")
        #expect(session.input.page == 2)
        #expect(session.input.context?.listRuleId == "home-list")
        #expect(loader.requests.map(\.url.absoluteString) == ["https://example.test/search?q=%E7%8C%AB&page=2"])
        #expect(loader.requests.first?.request?.scope == .search)
        #expect(loader.requests.first?.request?.headers?["X-Search-Rule"] == "1")
        #expect(session.requestLogs.first?.requestSummary.headerCount == 1)
        #expect(parser.parsedSearchRuleIDs == ["search"])
        #expect(parser.parsedSearchContexts.first.flatMap { $0 }?.pageId == "search")
        #expect(session.previewItems.map(\.title) == ["Search First"])
        #expect(session.pagination?.currentPage == 2)
        #expect(session.pagination?.nextPage == 3)
        #expect(session.pagination?.nextURL == "https://example.test/search?q=%E7%8C%AB&page=3")
        #expect(session.pagination?.source == .nextPageLink)
        #expect(session.issues.isEmpty)
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

private final class RuleDebugRecordingRuleParser: RuleParsingService, RulePaginationParsingService {
    let items: [ContentItem]
    private(set) var parsedListRuleIDs: [String?] = []
    private(set) var parsedSearchRuleIDs: [String?] = []
    private(set) var parsedSearchContexts: [ListContext?] = []
    var nextPageURL: String?

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

    func parseSearch(
        html: String,
        source: Source,
        searchRule: SearchRule,
        context: ListContext?
    ) throws -> [ContentItem] {
        self.parsedSearchRuleIDs.append(searchRule.id)
        self.parsedSearchContexts.append(context)

        return self.items.map { item in
            var mutableItem: ContentItem = item
            mutableItem.listContext = context
            return mutableItem
        }
    }

    func parseNextPageURL(
        html: String,
        source: Source,
        pagination: PaginationRule,
        currentURL: URL
    ) throws -> String? {
        return self.nextPageURL
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

private final class RuleDebugRecordingCandidateAnalyzer: RuleCandidateAnalyzingService {
    struct ListInput: Hashable {
        var ruleID: String?
        var pageID: String?
        var url: String?
    }

    struct PaginationInput: Hashable {
        var stage: RuleDebugStage
        var pageID: String?
        var ruleID: String?
        var currentURL: String?
        var urlTemplate: String?
    }

    private(set) var listInputs: [ListInput] = []
    private(set) var paginationInputs: [PaginationInput] = []

    func analyzeList(
        html: String,
        source: Source,
        listRule: ListRule?,
        pageID: String?,
        url: String?
    ) throws -> RuleCandidateReport {
        self.listInputs.append(
            ListInput(
                ruleID: listRule?.id,
                pageID: pageID,
                url: url
            )
        )

        return RuleCandidateReport(
            id: "list-report",
            sourceID: source.id,
            sourceName: source.name,
            stage: pageID == "search" ? .search : .list,
            pageID: pageID,
            ruleID: listRule?.id,
            url: url,
            generatedAt: Date(timeIntervalSince1970: 7_600),
            candidates: [
                self.candidate(
                    id: "candidate-item",
                    field: .item,
                    stage: pageID == "search" ? .search : .list,
                    selector: "article.card",
                    source: .repeatedDOMStructure
                )
            ],
            summary: RuleCandidateSummary(
                candidateCount: 1,
                highConfidenceCount: 1,
                warningCount: 0,
                coveredFields: [.item]
            )
        )
    }

    func analyzeDetail(
        html: String,
        source: Source,
        detailRule: DetailRule?,
        pageID: String?,
        url: String?
    ) throws -> RuleCandidateReport {
        return self.emptyReport(source: source, stage: .detail, pageID: pageID, ruleID: detailRule?.id, url: url)
    }

    func analyzeReader(
        html: String,
        source: Source,
        galleryRule: GalleryRule?,
        pageID: String?,
        url: String?
    ) throws -> RuleCandidateReport {
        return self.emptyReport(source: source, stage: .reader, pageID: pageID, ruleID: galleryRule?.id, url: url)
    }

    func analyzePagination(
        html: String,
        source: Source,
        pagination: PaginationRule?,
        stage: RuleDebugStage,
        pageID: String?,
        ruleID: String?,
        currentURL: String?,
        urlTemplate: String?
    ) throws -> RuleCandidateReport {
        self.paginationInputs.append(
            PaginationInput(
                stage: stage,
                pageID: pageID,
                ruleID: ruleID,
                currentURL: currentURL,
                urlTemplate: urlTemplate
            )
        )

        return RuleCandidateReport(
            id: "pagination-report",
            sourceID: source.id,
            sourceName: source.name,
            stage: stage,
            pageID: pageID,
            ruleID: ruleID,
            url: currentURL,
            generatedAt: Date(timeIntervalSince1970: 7_601),
            candidates: [
                self.candidate(
                    id: "candidate-next-page",
                    field: .nextPage,
                    stage: stage,
                    selector: "a.next",
                    source: .paginationLink
                )
            ],
            summary: RuleCandidateSummary(
                candidateCount: 1,
                highConfidenceCount: 1,
                warningCount: 0,
                coveredFields: [.nextPage]
            )
        )
    }

    private func candidate(
        id: String,
        field: RuleCandidateField,
        stage: RuleDebugStage,
        selector: String,
        source: RuleCandidateSource
    ) -> RuleCandidate {
        return RuleCandidate(
            id: id,
            field: field,
            stage: stage,
            selector: selector,
            selectorKind: .css,
            function: field == .nextPage ? .url : .raw,
            param: field == .nextPage ? "href" : nil,
            score: RuleCandidateScore(value: 0.9, confidence: .high, reasons: ["test"]),
            evidence: RuleCandidateEvidence(
                candidateCount: 1,
                matchedCount: 1,
                sampleValues: [selector],
                sampleAttributes: [:],
                ancestorHints: []
            ),
            warnings: [],
            source: source
        )
    }

    private func emptyReport(
        source: Source,
        stage: RuleDebugStage,
        pageID: String?,
        ruleID: String?,
        url: String?
    ) -> RuleCandidateReport {
        return RuleCandidateReport(
            id: "empty-report",
            sourceID: source.id,
            sourceName: source.name,
            stage: stage,
            pageID: pageID,
            ruleID: ruleID,
            url: url,
            generatedAt: Date(timeIntervalSince1970: 7_602),
            candidates: [],
            summary: RuleCandidateSummary(
                candidateCount: 0,
                highConfidenceCount: 0,
                warningCount: 0,
                coveredFields: []
            )
        )
    }
}
