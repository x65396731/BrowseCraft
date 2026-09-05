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
        catalogSourceID: String? = nil,
        reason: String? = nil,
        reasonDetail: String? = nil
    ) -> VideoGenerationOutcome {
        return VideoGenerationOutcome(
            jobID: UUID(),
            entryURL: entryURL,
            status: status,
            finishedAt: nil,
            catalogSourceID: catalogSourceID,
            reason: reason,
            reasonDetail: reasonDetail
        )
    }

    @Test func succeededOutcomesMoveTheirSourcesIntoThePersonalGroup() {
        let sources: [CatalogSource] = [Self.source("gimy-tv"), Self.source("kpkuang-org"), Self.source("jable-tv")]
        let grouping: CatalogSourceGrouping = CatalogSourceGrouping.make(
            catalogSources: sources,
            outcomes: [
                Self.outcome(entryURL: "https://gimy.tv/browse/1.html", status: "succeeded", catalogSourceID: "gimy-tv")
            ]
        )

        #expect(grouping.personalSources.map(\.id) == ["gimy-tv"])
        #expect(grouping.defaultSources.map(\.id) == ["kpkuang-org", "jable-tv"])
        #expect(grouping.failedOutcomes.isEmpty)
        #expect(grouping.personalEntryURLs["gimy-tv"] == "https://gimy.tv/browse/1.html")
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

    @Test func succeededOutcomeWhoseSourceIsNotInTheCatalogIsIgnored() {
        let grouping: CatalogSourceGrouping = CatalogSourceGrouping.make(
            catalogSources: [Self.source("a")],
            outcomes: [Self.outcome(entryURL: "https://z.invalid/", status: "succeeded", catalogSourceID: "gone")]
        )

        #expect(grouping.personalSources.isEmpty)
        #expect(grouping.defaultSources.map(\.id) == ["a"])
    }
}
