import Foundation
import Testing
@testable import BrowseCraft

// 中文注释：P2-3.3 覆盖 SwiftSoup parser 的列表调试 adapter，不影响生产解析接口。
struct SwiftSoupRuleDebugParserTests {
    @Test func debugParseListReportsCandidatesFieldsAndSkippedItems() throws {
        let source: Source = try Self.source()
        let listRule: ListRule = source.rule.primaryListRule
        let parser: SwiftSoupRuleParser = SwiftSoupRuleParser(
            urlResolver: URLResolvingService()
        )

        let result: RuleListDebugParseResult = try parser.debugParseList(
            html: Self.listHTML,
            source: source,
            listRule: listRule,
            context: nil,
            sections: nil
        )

        let itemLog: RuleDebugExtractionLog = try #require(
            result.extractionLogs.first { log in log.field == .item }
        )
        let titleLog: RuleDebugExtractionLog = try #require(
            result.extractionLogs.first { log in log.field == .title }
        )

        #expect(result.items.map(\.title) == ["Valid Item"])
        #expect(itemLog.candidateCount == 3)
        #expect(itemLog.outputCount == 1)
        #expect(titleLog.samples == ["Valid Item"])
        #expect(result.issues.contains { issue in
            issue.category == .fieldMissing && issue.field == .title
        })
        #expect(result.issues.contains { issue in
            issue.category == .fieldMissing && issue.field == .link
        })
    }

    private static let listHTML: String = """
    <main>
      <article class="card">
        <a class="title" href="/comics/valid">Valid Item</a>
        <img class="cover" src="/images/valid.jpg">
        <span class="badge">第01话</span>
      </article>
      <article class="card">
        <a class="title" href="/comics/no-title"></a>
      </article>
      <article class="card">
        <a class="title">No Link</a>
      </article>
    </main>
    """

    private static func source() throws -> Source {
        var rule: SiteRule = try JSONDecoder().decode(
            SiteRule.self,
            from: Data(RuleJSONFixtures.completeV2SiteRule.utf8)
        )
        rule.ruleSets?.listRules?[0].item = "article.card"
        rule.ruleSets?.listRules?[0].title = ".title"
        rule.ruleSets?.listRules?[0].link = ".title@href"
        rule.ruleSets?.listRules?[0].cover = ".cover@src"
        rule.ruleSets?.listRules?[0].latestText = ".badge"

        return Source(
            id: "debug-parser-source",
            name: "Debug Parser Source",
            baseURL: "https://example.test",
            type: .html,
            rule: rule,
            enabled: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
