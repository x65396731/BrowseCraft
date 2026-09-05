import BrowseCraftDomain
import Foundation
import Testing
@testable import BrowseCraft

struct PersonalRuleRetentionTests {
    private static let expiresAt: Date = Date(timeIntervalSince1970: 1_800_604_800)  // now + 7d

    @Test func remainingComponentsRoundUpToTheHour() {
        let now: Date = Self.expiresAt.addingTimeInterval(-(5 * 24 * 3600 + 23 * 3600 + 30 * 60))
        let remaining: (days: Int, hours: Int) = PersonalRuleRetentionPolicy.remainingComponents(expiresAt: Self.expiresAt, now: now)
        // 剩 5 天 23.5 小时 → 向上取整 → 6 天 0 小时
        #expect(remaining.days == 6)
        #expect(remaining.hours == 0)
        let late: (days: Int, hours: Int) = PersonalRuleRetentionPolicy.remainingComponents(expiresAt: Self.expiresAt, now: Self.expiresAt.addingTimeInterval(3600))
        #expect(late.days == 0 && late.hours == 0)
    }

    @Test func personalSourcesComeFromDecryptedOutcomesNotThePublicCatalog() {
        let mine: CatalogSource = CatalogSource(id: "mine", name: "mine", baseURL: "https://m.invalid", kind: .video, ruleJSON: "{}")
        let shared: CatalogSource = CatalogSource(id: "shared", name: "shared", baseURL: "https://s.invalid", kind: .video, ruleJSON: "{}")
        var succeeded: VideoGenerationOutcome = VideoGenerationOutcome(
            jobID: UUID(), entryURL: "https://m.invalid/list", status: "succeeded", finishedAt: nil,
            catalogSourceID: "mine", reason: nil, reasonDetail: nil
        )
        succeeded.expiresAt = Self.expiresAt
        succeeded.catalogSource = mine
        let grouping: CatalogSourceGrouping = CatalogSourceGrouping.make(catalogSources: [shared, mine], outcomes: [succeeded])

        #expect(grouping.personalSources == [mine])
        // 中文注释：万一公共目录还带着这条，也不重复显示。
        #expect(grouping.defaultSources == [shared])
        #expect(grouping.personalEntryURLs["mine"] == "https://m.invalid/list")
        #expect(grouping.personalOutcomes["mine"]?.expiresAt == Self.expiresAt)
    }
}
