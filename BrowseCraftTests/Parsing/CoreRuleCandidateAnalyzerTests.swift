import Foundation
import Testing
@testable import BrowseCraft
import BrowseCraftCore
import BrowseCraftDomain

// 中文注释：App 只验证 Source/rule 上下文到 Core Discovery 合同的接线。
struct CoreRuleCandidateAnalyzerTests {
    @Test func listAnalysisForwardsSourceAndRuleContextToCore() throws {
        let source = try Self.source()
        var nextID = 0
        let analyzer = CoreRuleCandidateAnalyzer(
            now: { Date(timeIntervalSince1970: 7_200) },
            idGenerator: {
                nextID += 1
                return "candidate-\(nextID)"
            }
        )

        let report = try analyzer.analyzeList(
            html: Self.listHTML,
            source: source,
            listRule: source.rule.ruleSets?.listRule(id: "home-list"),
            pageID: "home",
            url: "https://example.test/list"
        )

        #expect(report.sourceID == source.id)
        #expect(report.sourceName == source.name)
        #expect(report.stage == .list)
        #expect(report.pageID == "home")
        #expect(report.ruleID == "home-list")
        #expect(report.url == "https://example.test/list")
        #expect(report.candidates.contains { candidate in
            candidate.field == .item && candidate.selector == "article.card"
        })
    }

    private static let listHTML = """
    <main>
      <article class="card">
        <a class="title" href="/comics/one">第一话</a>
        <img class="cover" data-src="/images/one.jpg">
      </article>
      <article class="card">
        <a class="title" href="/comics/two">第二话</a>
        <img class="cover" src="/images/two.jpg">
      </article>
      <article class="card">
        <a class="title" href="/comics/three">第三话</a>
      </article>
    </main>
    """

    private static func source() throws -> Source {
        let rule = try JSONDecoder().decode(
            SiteRule.self,
            from: Data(RuleJSONFixtures.completeV2SiteRule.utf8)
        )
        return Source(
            id: "candidate-source",
            name: "Candidate Source",
            baseURL: "https://example.test",
            type: .html,
            rule: rule,
            enabled: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
