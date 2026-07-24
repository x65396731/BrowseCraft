import Foundation
import Testing
@testable import BrowseCraft

struct CoreComicRuleSourceParserTests {
    @Test func coreAdapterParsesV2ListDetailAndReaderDocuments() throws {
        let source = try Self.v2Source()
        let parser = Self.parser()
        let listRule = try #require(source.rule.availableListTabs.first?.list)
        let items = try parser.parseList(
            html: """
            <main>
              <article class="card" data-id="flow-1">
                <a class="title" href="../comics/flow-1">Core Flow</a>
                <img class="cover" src="../images/flow-1.jpg">
              </article>
            </main>
            """,
            source: source,
            listRule: listRule,
            context: nil,
            sections: nil,
            pageURL: URL(string: "https://example.test/catalog/page/1")!,
            currentPage: 1
        )

        #expect(items.count == 1)
        #expect(items[0].title == "Core Flow")
        #expect(items[0].detailURL == "https://example.test/catalog/comics/flow-1")
        #expect(items[0].coverURL == "https://example.test/catalog/images/flow-1.jpg")
        #expect(items[0].idCode == "flow-1")

        let detailRule = try #require(
            RuleResolver().resolve(source.rule).primaryDetailRule
        )
        let detail = try parser.parseDetail(
            html: """
            <main>
              <div class="chapter" data-id="chapter-1">
                <span class="chapter-title">第01话</span>
                <a class="chapter-link" href="/chapters/flow-1">Read</a>
              </div>
            </main>
            """,
            source: source,
            detailRule: detailRule,
            pageURL: items[0].detailURL,
            context: nil
        )

        #expect(detail.chapters.map(\.title) == ["第01话"])
        #expect(
            detail.chapters.map(\.url)
                == ["https://example.test/chapters/flow-1"]
        )

        let galleryRule = try #require(
            RuleResolver().resolve(source.rule).primaryGalleryRule
        )
        let chapter = try parser.parseReader(
            html: """
            <main>
              <img class="page" data-src="/images/page-1.jpg">
            </main>
            """,
            source: source,
            galleryRule: galleryRule,
            pageURL: detail.chapters[0].url,
            context: nil
        )

        #expect(
            chapter.pageImageURLs
                == ["https://example.test/images/page-1.jpg"]
        )
    }

    @Test func coreAdapterKeepsLegacyEmbeddedCoverFallbackDuringMigration() throws {
        let source = Self.embeddedCoverSource()
        let parser = Self.parser()
        let items = try parser.parseList(
            html: """
            <main>
              <div class="comic-card-wrapper">
                <a href="/comic/5571">小栗子到我家</a>
              </div>
              <script>
                window.__DATA__ = {
                  "items": [{
                    "url": "/comic/5571",
                    "title": "小栗子到我家",
                    "imageUrl": "/images/cover-5571.jpg"
                  }]
                };
              </script>
            </main>
            """,
            source: source,
            listRule: source.rule.primaryListRule,
            context: nil,
            sections: nil,
            pageURL: URL(string: "https://example.test/updates")!,
            currentPage: 1
        )

        #expect(items.count == 1)
        #expect(items[0].detailURL == "https://example.test/comic/5571")
        #expect(items[0].coverURL == "https://example.test/images/cover-5571.jpg")
    }

    private static func parser() -> CoreComicRuleSourceParser {
        return CoreComicRuleSourceParser(
            fallbackParser: SwiftSoupComicRuleSourceParser(
                urlResolver: URLResolvingService()
            )
        )
    }

    private static func v2Source() throws -> Source {
        var rule = try JSONDecoder().decode(
            SiteRule.self,
            from: Data(RuleJSONFixtures.completeV2SiteRule.utf8)
        )
        rule.list.item = ".legacy-list-should-not-match"
        rule.detail = nil
        rule.gallery = nil
        return Source(
            id: "core-adapter-v2",
            name: "Core Adapter V2",
            baseURL: "https://example.test",
            type: .html,
            rule: rule,
            enabled: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private static func embeddedCoverSource() -> Source {
        let rule = SiteRule(
            version: 1,
            name: "Embedded Cover",
            baseUrl: "https://example.test",
            list: ListRule(
                id: "updates",
                url: "https://example.test/updates",
                item: ".comic-card-wrapper",
                title: "a",
                link: "a@href",
                cover: "img@src",
                type: .comic
            )
        )
        return Source(
            id: "core-adapter-legacy",
            name: "Core Adapter Legacy",
            baseURL: "https://example.test",
            type: .html,
            rule: rule,
            enabled: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
