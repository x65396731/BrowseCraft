import BrowseCraftDomain
import Foundation
import Testing
@testable import BrowseCraft

struct CatalogSourceGroupingTests {
    private static func source(_ id: String, section: CatalogSourceSection? = .example) -> CatalogSource {
        return CatalogSource(id: id, name: id, baseURL: "https://\(id).invalid", kind: .video, ruleJSON: "{}", section: section)
    }

    private static func outcome(
        entryURL: String,
        status: String,
        catalogSource: CatalogSource? = nil,
        reason: String? = nil,
        reasonDetail: String? = nil
    ) -> VideoGenerationOutcome {
        var outcome: VideoGenerationOutcome = VideoGenerationOutcome(
            jobID: UUID(),
            entryURL: entryURL,
            status: status,
            finishedAt: nil,
            catalogSourceID: catalogSource?.id,
            reason: reason,
            reasonDetail: reasonDetail
        )
        outcome.catalogSource = catalogSource
        return outcome
    }

    @Test func succeededOutcomesFormThePersonalGroup() {
        let gimy: CatalogSource = Self.source("gimy-tv--browse-2-html")
        let grouping: CatalogSourceGrouping = CatalogSourceGrouping.make(
            catalogSources: [Self.source("kpkuang-org"), Self.source("jable-tv")],
            outcomes: [Self.outcome(entryURL: "https://gimy.tv/browse/2.html", status: "succeeded", catalogSource: gimy)]
        )

        #expect(grouping.personalSources.map(\.id) == ["gimy-tv--browse-2-html"])
        #expect(grouping.defaultSources.map(\.id) == ["kpkuang-org", "jable-tv"])
        #expect(grouping.failedOutcomes.isEmpty)
        #expect(grouping.personalEntryURLs["gimy-tv--browse-2-html"] == "https://gimy.tv/browse/2.html")
    }

    @Test func withoutOutcomesEverythingIsDefault() {
        let sources: [CatalogSource] = [Self.source("a"), Self.source("b")]
        let grouping: CatalogSourceGrouping = CatalogSourceGrouping.make(catalogSources: sources, outcomes: [])

        #expect(grouping.defaultSources == sources)
        #expect(grouping.personalSources.isEmpty)
    }

    @Test("发现只收 example 与（Debug）internal；没有 section 或用户分享的不展示，示例最多 6 条、保持服务端顺序")
    func discoverKeepsOnlyKnownSectionsAndCapsExamples() {
        let examples: [CatalogSource] = (1 ... 7).map { index in Self.source("example-\(index)") }
        let grouping: CatalogSourceGrouping = CatalogSourceGrouping.make(
            catalogSources: [
                Self.source("preset", section: .internalTest),
                Self.source("legacy", section: nil),
                Self.source("shared", section: .shared)
            ] + examples,
            outcomes: []
        )

        #expect(grouping.exampleSources.map(\.id) == (1 ... 6).map { index in "example-\(index)" })
        #if DEBUG
        #expect(grouping.internalSources.map(\.id) == ["preset"])
        #else
        #expect(grouping.internalSources.isEmpty)
        #endif
    }

    @Test func failedOutcomesAreListedOncePerEntryURLKeepingTheNewest() {
        let grouping: CatalogSourceGrouping = CatalogSourceGrouping.make(
            catalogSources: [],
            outcomes: [
                Self.outcome(entryURL: "https://x.invalid/", status: "failed", reason: "siteNotSupported", reasonDetail: "episodeLayoutUnsupported"),
                Self.outcome(entryURL: "https://x.invalid/", status: "failed", reason: "temporaryFailure"),
                Self.outcome(entryURL: "https://y.invalid/", status: "failed", reason: "siteUnreachable")
            ]
        )

        #expect(grouping.failedOutcomes.map { $0.entryURL } == ["https://x.invalid/", "https://y.invalid/"])
        #expect(grouping.failedOutcomes.first?.reasonDetail == "episodeLayoutUnsupported")
    }

    private static func publicSource(_ id: String, baseURL: String, pagesJSON: String) -> CatalogSource {
        return CatalogSource(
            id: id, name: "book.sfacg.com", baseURL: baseURL, kind: .book, ruleJSON: "{\"pages\":\(pagesJSON)}", section: .example
        )
    }

    @Test func sameHostPublicSourcesExposeTheirOwnEntryURLs() {
        let all: CatalogSource = Self.publicSource(
            "sfacg-com--list", baseURL: "https://book.sfacg.com/",
            pagesJSON: "[{\"type\":\"list\",\"url\":\"https://book.sfacg.com/List/\"}]"
        )
        let category: CatalogSource = Self.publicSource(
            "sfacg-com--list-tid-21", baseURL: "https://book.sfacg.com/",
            pagesJSON: "[{\"type\":\"list\",\"url\":\"https://book.sfacg.com/List/?tid=21\"}]"
        )
        let grouping: CatalogSourceGrouping = CatalogSourceGrouping.make(catalogSources: [all, category], outcomes: [])

        #expect(grouping.defaultEntryURLs["sfacg-com--list"] == "https://book.sfacg.com/List/")
        #expect(grouping.defaultEntryURLs["sfacg-com--list-tid-21"] == "https://book.sfacg.com/List/?tid=21")
    }

    @Test func singleSourceOfAHostKeepsShowingTheBaseURL() {
        let only: CatalogSource = Self.publicSource(
            "biquhua", baseURL: "https://www.biquhua.com/",
            pagesJSON: "[{\"type\":\"list\",\"url\":\"https://www.biquhua.com/top/all_0_1.html\"}]"
        )
        let grouping: CatalogSourceGrouping = CatalogSourceGrouping.make(catalogSources: [only, Self.source("a")], outcomes: [])

        #expect(grouping.defaultEntryURLs.isEmpty)
    }

    @Test func relativePageURLIsResolvedAgainstTheBaseURL() {
        #expect(
            CatalogSourceGrouping.ruleEntryURL(
                ruleJSON: "{\"pages\":[{\"url\":\"/vodtype/1/\"}]}",
                baseURL: "https://www.kpkuang.org/"
            ) == "https://www.kpkuang.org/vodtype/1/"
        )
    }

    @Test func templatedOrMissingPageURLsAreSkipped() {
        #expect(
            CatalogSourceGrouping.ruleEntryURL(
                ruleJSON: "{\"pages\":[{\"url\":\"https://mycomic.com/cn?page={page}\"},{\"url\":null},{\"url\":\"https://mycomic.com/cn/rank\"}]}",
                baseURL: "https://mycomic.com/cn"
            ) == "https://mycomic.com/cn/rank"
        )
        #expect(CatalogSourceGrouping.ruleEntryURL(ruleJSON: "{\"list\":{}}", baseURL: "https://x.invalid/") == nil)
    }

    @Test func succeededOutcomeWithoutDecryptedSourceIsNotListed() {
        let grouping: CatalogSourceGrouping = CatalogSourceGrouping.make(
            catalogSources: [Self.source("a")],
            outcomes: [Self.outcome(entryURL: "https://z.invalid/", status: "succeeded", catalogSource: nil)]
        )

        #expect(grouping.personalSources.isEmpty)
        #expect(grouping.defaultSources.map(\.id) == ["a"])
    }
}
