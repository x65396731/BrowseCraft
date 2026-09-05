import BrowseCraftDomain
import Foundation
import Testing
@testable import BrowseCraft

struct PersonalRuleRetentionTests {
    private static let receivedAt: Date = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func retentionIsSevenDaysFromReceipt() {
        let expires: Date = PersonalRuleRetentionPolicy.expiresAt(receivedAt: Self.receivedAt)
        #expect(expires.timeIntervalSince(Self.receivedAt) == 7 * 24 * 3600)
        #expect(PersonalRuleRetentionPolicy.isExpired(receivedAt: Self.receivedAt, now: expires) )
        #expect(PersonalRuleRetentionPolicy.isExpired(receivedAt: Self.receivedAt, now: expires.addingTimeInterval(-1)) == false)
    }

    @Test func remainingComponentsRoundUpToTheHour() {
        let now: Date = Self.receivedAt.addingTimeInterval(24 * 3600 + 30 * 60)  // 1 天 0.5 小时后
        let remaining: (days: Int, hours: Int) = PersonalRuleRetentionPolicy.remainingComponents(receivedAt: Self.receivedAt, now: now)
        // 剩 5 天 23.5 小时 → 向上取整 5 天 24 小时 = 6 天 0 小时
        #expect(remaining.days == 6)
        #expect(remaining.hours == 0)
        let late: (days: Int, hours: Int) = PersonalRuleRetentionPolicy.remainingComponents(receivedAt: Self.receivedAt, now: Self.receivedAt.addingTimeInterval(8 * 24 * 3600))
        #expect(late.days == 0 && late.hours == 0)
    }

    @Test func hiddenIDsLeaveBothGroupsAndFailedRows() {
        let sources: [CatalogSource] = [
            CatalogSource(id: "mine", name: "mine", baseURL: "https://m.invalid", kind: .video, ruleJSON: "{}"),
            CatalogSource(id: "shared", name: "shared", baseURL: "https://s.invalid", kind: .video, ruleJSON: "{}")
        ]
        let failedJob: UUID = UUID()
        let outcomes: [VideoGenerationOutcome] = [
            VideoGenerationOutcome(jobID: UUID(), entryURL: "https://m.invalid/a", status: "succeeded", finishedAt: nil, catalogSourceID: "mine", reason: nil, reasonDetail: nil),
            VideoGenerationOutcome(jobID: failedJob, entryURL: "https://x.invalid/", status: "failed", finishedAt: nil, catalogSourceID: nil, reason: "temporaryFailure", reasonDetail: nil)
        ]
        let grouping: CatalogSourceGrouping = CatalogSourceGrouping.make(
            catalogSources: sources,
            outcomes: outcomes,
            hiddenIDs: ["mine", failedJob.uuidString]
        )
        #expect(grouping.personalSources.isEmpty)
        #expect(grouping.defaultSources.map(\.id) == ["shared"])
        #expect(grouping.failedOutcomes.isEmpty)
    }

    @Test func userDefaultsStoreKeepsFirstReceiptAndHidesPerUser() {
        let defaults: UserDefaults = UserDefaults(suiteName: "PersonalRuleRetentionTests.\(UUID().uuidString)")!
        let store: UserDefaultsPersonalRuleReceiptStore = UserDefaultsPersonalRuleReceiptStore(userDefaults: defaults)
        store.recordReceiptIfAbsent(catalogSourceID: "mine", userID: "u1", receivedAt: Self.receivedAt)
        store.recordReceiptIfAbsent(catalogSourceID: "mine", userID: "u1", receivedAt: Self.receivedAt.addingTimeInterval(3600))
        #expect(store.receipts(userID: "u1") == [PersonalRuleReceipt(catalogSourceID: "mine", receivedAt: Self.receivedAt)])
        #expect(store.receipts(userID: "u2").isEmpty)
        store.hide(id: "mine", userID: "u1")
        #expect(store.hiddenIDs(userID: "u1") == ["mine"])
        #expect(store.receipts(userID: "u1").isEmpty)
        #expect(store.hiddenIDs(userID: "u2").isEmpty)
    }
}
