import BrowseCraftDomain
import Foundation
import Testing
@testable import BrowseCraft

struct CatalogSourceGroupingTests {
    private static func source(_ id: String) -> CatalogSource {
        return CatalogSource(id: id, name: id, baseURL: "https://\(id).invalid", kind: .video, ruleJSON: "{}")
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

    @Test func succeededOutcomeWithoutDecryptedSourceIsNotListed() {
        let grouping: CatalogSourceGrouping = CatalogSourceGrouping.make(
            catalogSources: [Self.source("a")],
            outcomes: [Self.outcome(entryURL: "https://z.invalid/", status: "succeeded", catalogSource: nil)]
        )

        #expect(grouping.personalSources.isEmpty)
        #expect(grouping.defaultSources.map(\.id) == ["a"])
    }
}
