import Foundation
import Testing
@testable import BrowseCraft

// P2-7.2 covers the list candidate MVP without connecting it to UI or rule saving.
struct SwiftSoupRuleSelectorFinderTests {
    @Test func listSelectorFinderRecommendsItemAndFieldCandidates() throws {
        let source: Source = try Self.source()
        var nextID: Int = 0
        let selectorFinder: SwiftSoupRuleSelectorFinder = SwiftSoupRuleSelectorFinder(
            now: {
                return Date(timeIntervalSince1970: 7_200)
            },
            idGenerator: {
                nextID += 1
                return "candidate-\(nextID)"
            }
        )

        let report: RuleCandidateReport = try selectorFinder.analyzeList(
            html: Self.listHTML,
            source: source,
            listRule: source.rule.ruleSets?.listRule(id: "home-list"),
            pageID: "home",
            url: "https://example.test/list"
        )

        let itemCandidate: RuleCandidate = try #require(report.candidates.first { candidate in
            return candidate.field == .item
        })
        let titleCandidate: RuleCandidate = try #require(report.candidates.first { candidate in
            return candidate.field == .title
        })
        let linkCandidate: RuleCandidate = try #require(report.candidates.first { candidate in
            return candidate.field == .link
        })
        let coverCandidate: RuleCandidate = try #require(report.candidates.first { candidate in
            return candidate.field == .cover
        })
        let latestCandidate: RuleCandidate = try #require(report.candidates.first { candidate in
            return candidate.field == .latestText
        })

        #expect(report.sourceID == source.id)
        #expect(report.stage == .list)
        #expect(report.pageID == "home")
        #expect(report.ruleID == "home-list")
        #expect(report.summary.coveredFields.contains(.item))
        #expect(report.summary.coveredFields.contains(.title))
        #expect(itemCandidate.selector == "article.card")
        #expect(itemCandidate.evidence.candidateCount == 3)
        #expect(itemCandidate.score.confidence == .high)
        #expect(titleCandidate.selector == "a.title")
        #expect(titleCandidate.evidence.sampleValues == ["第一话", "第二话", "第三话"])
        #expect(linkCandidate.function == .url)
        #expect(linkCandidate.param == "href")
        #expect(coverCandidate.param == "data-src|src")
        #expect(coverCandidate.warnings.contains { warning in
            return warning.category == .missingRequiredField
        })
        #expect(latestCandidate.selector == ".badge")
    }

    @Test func detailSelectorFinderRecommendsChapterCandidatesWithoutRecommendationNoise() throws {
        let source: Source = try Self.source()
        var nextID: Int = 0
        let selectorFinder: SwiftSoupRuleSelectorFinder = SwiftSoupRuleSelectorFinder(
            now: {
                return Date(timeIntervalSince1970: 7_300)
            },
            idGenerator: {
                nextID += 1
                return "detail-candidate-\(nextID)"
            }
        )

        let report: RuleCandidateReport = try selectorFinder.analyzeDetail(
            html: Self.detailHTML,
            source: source,
            detailRule: source.rule.ruleSets?.detailRule(id: "detail"),
            pageID: "detail",
            url: "https://example.test/comics/100"
        )

        let containerCandidate: RuleCandidate = try #require(report.candidates.first { candidate in
            return candidate.field == .chapterContainer
        })
        let itemCandidate: RuleCandidate = try #require(report.candidates.first { candidate in
            return candidate.field == .chapterItem
        })
        let titleCandidate: RuleCandidate = try #require(report.candidates.first { candidate in
            return candidate.field == .chapterTitle
        })
        let linkCandidate: RuleCandidate = try #require(report.candidates.first { candidate in
            return candidate.field == .chapterLink
        })

        #expect(report.stage == .detail)
        #expect(report.pageID == "detail")
        #expect(report.ruleID == "detail")
        #expect(containerCandidate.selector == "ul.chapters")
        #expect(itemCandidate.selector == "li.chapter")
        #expect(itemCandidate.evidence.candidateCount == 3)
        #expect(titleCandidate.selector == "a[href]")
        #expect(titleCandidate.evidence.sampleValues == ["第01话", "第02话", "第03话"])
        #expect(linkCandidate.param == "href")
        #expect(report.candidates.allSatisfy { candidate in
            return candidate.evidence.sampleValues.contains("推荐 第99话") == false
        })
    }

    @Test func readerSelectorFinderRecommendsPageImagesWithoutAdOrAvatarNoise() throws {
        let source: Source = try Self.source()
        var nextID: Int = 0
        let selectorFinder: SwiftSoupRuleSelectorFinder = SwiftSoupRuleSelectorFinder(
            now: {
                return Date(timeIntervalSince1970: 7_400)
            },
            idGenerator: {
                nextID += 1
                return "reader-candidate-\(nextID)"
            }
        )

        let report: RuleCandidateReport = try selectorFinder.analyzeReader(
            html: Self.readerHTML,
            source: source,
            galleryRule: source.rule.ruleSets?.galleryRule(id: "reader-gallery"),
            pageID: "reader",
            url: "https://example.test/chapters/100-1"
        )

        let imageCandidate: RuleCandidate = try #require(report.candidates.first { candidate in
            return candidate.field == .image
        })

        #expect(report.stage == .reader)
        #expect(report.pageID == "reader")
        #expect(report.ruleID == "reader-gallery")
        #expect(imageCandidate.selector == "img.page")
        #expect(imageCandidate.function == .attr)
        #expect(imageCandidate.param == "data-src|data-original|data-lazy-src|src")
        #expect(imageCandidate.evidence.candidateCount == 3)
        #expect(imageCandidate.evidence.sampleValues == [
            "/pages/001.jpg",
            "/pages/002.jpg",
            "/pages/003.jpg"
        ])
        #expect(imageCandidate.score.confidence == .high)
        #expect(report.candidates.allSatisfy { candidate in
            return candidate.evidence.sampleValues.contains("/ads/banner.jpg") == false
        })
        #expect(report.candidates.allSatisfy { candidate in
            return candidate.evidence.sampleValues.contains("/avatars/user.jpg") == false
        })
    }

    @Test func paginationAnalyzerRecommendsNextLinkAndPagePlaceholder() throws {
        let source: Source = try Self.source()
        var nextID: Int = 0
        let selectorFinder: SwiftSoupRuleSelectorFinder = SwiftSoupRuleSelectorFinder(
            now: {
                return Date(timeIntervalSince1970: 7_500)
            },
            idGenerator: {
                nextID += 1
                return "pagination-candidate-\(nextID)"
            }
        )

        let report: RuleCandidateReport = try selectorFinder.analyzePagination(
            html: Self.paginationHTML,
            source: source,
            pagination: PaginationRule(
                nextPage: nil,
                pagePlaceholder: "{page}",
                maxPages: 10,
                stopWhenEmpty: true
            ),
            stage: .search,
            pageID: "search",
            ruleID: "search",
            currentURL: "https://example.test/search?q=cat&page=1",
            urlTemplate: "https://example.test/search?q={keyword:}&page={page}"
        )

        let linkCandidate: RuleCandidate = try #require(report.candidates.first { candidate in
            return candidate.source == .paginationLink
        })
        let placeholderCandidate: RuleCandidate = try #require(report.candidates.first { candidate in
            return candidate.source == .manualSeed
        })

        #expect(report.stage == .search)
        #expect(report.pageID == "search")
        #expect(report.ruleID == "search")
        #expect(linkCandidate.field == .nextPage)
        #expect(linkCandidate.selector == "a.next")
        #expect(linkCandidate.function == .url)
        #expect(linkCandidate.param == "href")
        #expect(linkCandidate.evidence.sampleValues == ["/search?q=cat&page=2"])
        #expect(placeholderCandidate.field == .nextPage)
        #expect(placeholderCandidate.selectorKind == .current)
        #expect(placeholderCandidate.param == "{page}")
        #expect(placeholderCandidate.evidence.sampleAttributes["pagePlaceholder"] == ["{page}"])
        #expect(report.candidates.allSatisfy { candidate in
            return candidate.evidence.sampleValues.contains("/search?q=cat&page=0") == false
        })
    }

    private static let listHTML: String = """
    <main>
      <nav>
        <a class="title" href="/nav">导航链接</a>
      </nav>
      <article class="card" data-id="one">
        <a class="title" href="/comics/one">第一话</a>
        <img class="cover" data-src="/images/one.jpg">
        <span class="badge">第01话</span>
      </article>
      <article class="card" data-id="two">
        <a class="title" href="/comics/two">第二话</a>
        <img class="cover" src="/images/two.jpg">
        <span class="badge">第02话</span>
      </article>
      <article class="card" data-id="three">
        <a class="title" href="/comics/three">第三话</a>
      </article>
    </main>
    """

    private static let detailHTML: String = """
    <main>
      <nav>
        <a href="/chapters/nav">导航 第00话</a>
      </nav>
      <section class="chapters-zone">
        <ul class="chapters">
          <li class="chapter"><a href="/chapters/1">第01话</a></li>
          <li class="chapter"><a href="/chapters/2">第02话</a></li>
          <li class="chapter"><a href="/chapters/3">第03话</a></li>
        </ul>
      </section>
      <section class="related">
        <a href="/chapters/99">推荐 第99话</a>
      </section>
      <section class="language">
        <a href="/chapters/en">Chapter EN</a>
      </section>
    </main>
    """

    private static let readerHTML: String = """
    <main class="reader">
      <header>
        <img class="logo" src="/assets/logo.png">
      </header>
      <section class="reader-pages">
        <img class="page" data-src="/pages/001.jpg" width="900" height="1400" alt="page 1">
        <img class="page" data-src="/pages/002.jpg" width="900" height="1400" alt="page 2">
        <img class="page" src="/pages/003.jpg" width="900" height="1400" alt="page 3">
      </section>
      <aside class="ads">
        <img class="banner" src="/ads/banner.jpg">
      </aside>
      <section class="comments">
        <img class="avatar" src="/avatars/user.jpg">
      </section>
      <section class="related">
        <img class="thumb" src="/covers/related.jpg">
      </section>
    </main>
    """

    private static let paginationHTML: String = """
    <main>
      <nav class="pager">
        <a class="prev" href="/search?q=cat&page=0">上一页</a>
        <a class="page current" href="/search?q=cat&page=1">1</a>
        <a class="next" rel="next" href="/search?q=cat&page=2" aria-label="Next page">下一页</a>
      </nav>
      <aside class="related">
        <a class="next" href="/related?page=2">相关推荐下一页</a>
      </aside>
    </main>
    """

    private static func source() throws -> Source {
        let rule: SiteRule = try JSONDecoder().decode(
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
