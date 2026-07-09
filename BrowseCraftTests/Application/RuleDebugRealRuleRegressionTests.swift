import Foundation
import Testing
@testable import BrowseCraft

struct RuleDebugRealRuleRegressionTests {
    @Test func fieldMissingRegressionReportsSkippedItems() async throws {
        let source: Source = try Self.v2Source(listURL: "https://example.test/list/1")
        let loader: RuleDebugRegressionPageContentLoader = RuleDebugRegressionPageContentLoader(
            html: Self.fieldMissingHTML
        )
        let useCase: ListDebugUseCase = Self.useCase(loader: loader)

        let session: RuleDebugSession = await useCase.execute(
            source: source,
            listTab: source.rule.availableListTabs.first,
            page: 1
        )

        let itemLog: RuleDebugExtractionLog = try #require(
            session.extractionLogs.first { log in log.field == .item }
        )

        #expect(session.status == .succeeded)
        #expect(session.previewItems.map(\.title) == ["Valid Item"])
        #expect(itemLog.candidateCount == 3)
        #expect(itemLog.outputCount == 1)
        #expect(session.issues.contains { issue in
            issue.category == .fieldMissing && issue.field == .title
        })
        #expect(session.issues.contains { issue in
            issue.category == .fieldMissing && issue.field == .link
        })
    }

    @Test func urlResolveRegressionCoversRequestAndPreviewLinks() async throws {
        let source: Source = try Self.v2Source(listURL: "/relative/list/{page}")
        let loader: RuleDebugRegressionPageContentLoader = RuleDebugRegressionPageContentLoader(
            html: Self.relativeURLHTML
        )
        let useCase: ListDebugUseCase = Self.useCase(loader: loader)

        let session: RuleDebugSession = await useCase.execute(
            source: source,
            listTab: source.rule.availableListTabs.first,
            page: 3
        )

        #expect(loader.requests.map(\.url.absoluteString) == ["https://example.test/relative/list/3"])
        #expect(session.status == .succeeded)
        #expect(session.requestLogs.first?.url == "https://example.test/relative/list/3")
        #expect(session.previewItems.first?.detailURL == "https://example.test/comics/relative-one")
        #expect(session.previewItems.first?.coverURL == "https://example.test/images/relative-one.jpg")
    }

    private static let fieldMissingHTML: String = """
    <main>
      <article class="card">
        <a class="title" href="/comics/valid">Valid Item</a>
        <img class="cover" src="/images/valid.jpg">
      </article>
      <article class="card">
        <a class="title" href="/comics/no-title"></a>
      </article>
      <article class="card">
        <a class="title">No Link</a>
      </article>
    </main>
    """

    private static let relativeURLHTML: String = """
    <main>
      <article class="card">
        <a class="title" href="/comics/relative-one">Relative One</a>
        <img class="cover" src="/images/relative-one.jpg">
      </article>
    </main>
    """

    private static func useCase(loader: RuleDebugRegressionPageContentLoader) -> ListDebugUseCase {
        let urlResolver: URLResolvingService = URLResolvingService()

        return ListDebugUseCase(
            pageContentLoader: loader,
            ruleParser: SwiftSoupRuleParser(urlResolver: urlResolver),
            urlResolver: urlResolver,
            now: Self.fixedDate,
            idGenerator: Self.idGenerator()
        )
    }

    private static func v2Source(listURL: String) throws -> Source {
        var rule: SiteRule = try JSONDecoder().decode(
            SiteRule.self,
            from: Data(RuleJSONFixtures.completeV2SiteRule.utf8)
        )
        rule.ruleSets?.listRules?[0].url = listURL
        rule.ruleSets?.listRules?[0].item = "article.card"
        rule.ruleSets?.listRules?[0].title = ".title"
        rule.ruleSets?.listRules?[0].link = ".title@href"
        rule.ruleSets?.listRules?[0].cover = ".cover@src"
        rule.pages?[0].sections = nil

        return Source(
            id: "debug-regression-source",
            name: "Debug Regression Source",
            baseURL: "https://example.test",
            type: .html,
            rule: rule,
            enabled: true,
            createdAt: Self.fixedDate(),
            updatedAt: Self.fixedDate()
        )
    }

    private static func fixedDate() -> Date {
        return Date(timeIntervalSince1970: 4_000)
    }

    private static func idGenerator() -> () -> String {
        var nextID: Int = 0
        return {
            nextID += 1
            return "regression-\(nextID)"
        }
    }
}

private final class RuleDebugRegressionPageContentLoader: PageContentLoader {
    struct RecordedRequest: Hashable {
        var url: URL
        var request: RequestConfig?
    }

    let html: String
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
