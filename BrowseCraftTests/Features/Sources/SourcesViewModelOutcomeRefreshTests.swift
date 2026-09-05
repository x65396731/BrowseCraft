import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft
import BrowseCraftDomain

/// 推送到达/点开 → SourcesViewModel 刷新目录并读取个人生成终态；分组按 outcomes 计算。
@MainActor
struct SourcesViewModelOutcomeRefreshTests {
    private typealias Harness = ViewModelTestHarness

    private struct StubTokenProvider: PortalAccessTokenProviding {
        let token: String?
        func validAccessToken() async -> String? { return self.token }
    }

    private actor ScriptedOutcomesClient: VideoGenerationOutcomesFetching {
        private(set) var callCount: Int = 0
        private let outcomes: [VideoGenerationOutcome]

        init(outcomes: [VideoGenerationOutcome]) {
            self.outcomes = outcomes
        }

        func fetchOutcomes(accessToken: String) async throws -> [VideoGenerationOutcome] {
            self.callCount += 1
            return self.outcomes
        }
    }

    private static let failedOutcome: VideoGenerationOutcome = VideoGenerationOutcome(
        jobID: UUID(),
        entryURL: "https://comic-walker.com/",
        status: "failed",
        finishedAt: nil,
        catalogSourceID: nil,
        reason: "siteNotSupported",
        reasonDetail: "episodeLayoutUnsupported"
    )

    @Test func pushRefreshRequestLoadsOutcomesAndExposesFailedGeneration() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let client: ScriptedOutcomesClient = ScriptedOutcomesClient(outcomes: [Self.failedOutcome])
        let requests: RuleGenerationOutcomeRefreshRequests = RuleGenerationOutcomeRefreshRequests()
        let viewModel: SourcesViewModel = Harness.makeSourcesViewModel(
            database: database,
            resolver: Harness.resolver(),
            loadVideoGenerationOutcomesUseCase: LoadVideoGenerationOutcomesUseCase(
                outcomesClient: client,
                accessTokenProvider: StubTokenProvider(token: "access")
            ),
            outcomeRefreshRequests: requests
        )
        #expect(viewModel.videoGenerationOutcomesLoad == nil)

        requests.request(.presented)

        let refreshed: Bool = await Harness.waitUntil {
            viewModel.failedGenerationOutcomes.count == 1
        }
        #expect(refreshed)
        // 中文注释：前台到达只刷新，不导航。
        #expect(viewModel.catalogPresentationRevision == 0)

        requests.request(.opened)
        let navigated: Bool = await Harness.waitUntil {
            viewModel.catalogPresentationRevision == 1
        }
        #expect(navigated)
        // 中文注释：点开只记「待处理」，表单要等 RootView 确认主界面就绪后才打开。
        #expect(viewModel.pendingCatalogPresentation)
        #expect(viewModel.catalogSheetRevision == 0)
        #expect(viewModel.presentCatalogSheetIfPending())
        #expect(viewModel.pendingCatalogPresentation == false)
        #expect(viewModel.catalogSheetRevision == 1)
        #expect(viewModel.presentCatalogSheetIfPending() == false)
        #expect(viewModel.failedGenerationOutcomes.first?.reasonDetail == "episodeLayoutUnsupported")
        #expect(viewModel.personalCatalogSources.isEmpty)
        #expect(viewModel.isPersonalCatalogSignInRequired == false)
        // 中文注释：到达一次 + 点开一次 = 两次刷新。
        #expect(await client.callCount == 2)
    }

    @Test func withoutSessionPersonalGroupAsksForSignIn() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let client: ScriptedOutcomesClient = ScriptedOutcomesClient(outcomes: [Self.failedOutcome])
        let viewModel: SourcesViewModel = Harness.makeSourcesViewModel(
            database: database,
            resolver: Harness.resolver(),
            loadVideoGenerationOutcomesUseCase: LoadVideoGenerationOutcomesUseCase(
                outcomesClient: client,
                accessTokenProvider: StubTokenProvider(token: nil)
            )
        )

        await viewModel.refreshCatalogSources()

        #expect(viewModel.isPersonalCatalogSignInRequired)
        #expect(viewModel.failedGenerationOutcomes.isEmpty)
        #expect(await client.callCount == 0)
    }

    private final class InMemoryReceiptStore: PersonalRuleReceiptStoring, @unchecked Sendable {
        var receiptsByUser: [String: [String: Date]] = [:]
        var hiddenByUser: [String: Set<String>] = [:]

        func receipts(userID: String) -> [PersonalRuleReceipt] {
            return (self.receiptsByUser[userID] ?? [:]).map { PersonalRuleReceipt(catalogSourceID: $0.key, receivedAt: $0.value) }
        }
        func recordReceiptIfAbsent(catalogSourceID: String, userID: String, receivedAt: Date) {
            if self.receiptsByUser[userID, default: [:]][catalogSourceID] == nil {
                self.receiptsByUser[userID, default: [:]][catalogSourceID] = receivedAt
            }
        }
        func hiddenIDs(userID: String) -> Set<String> { return self.hiddenByUser[userID] ?? [] }
        func hide(id: String, userID: String) {
            self.hiddenByUser[userID, default: []].insert(id)
            self.receiptsByUser[userID]?.removeValue(forKey: id)
        }
    }

    @Test func deletingAFailedOutcomeHidesItLocally() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let store: InMemoryReceiptStore = InMemoryReceiptStore()
        let client: ScriptedOutcomesClient = ScriptedOutcomesClient(outcomes: [Self.failedOutcome])
        let viewModel: SourcesViewModel = Harness.makeSourcesViewModel(
            database: database,
            resolver: Harness.resolver(),
            loadVideoGenerationOutcomesUseCase: LoadVideoGenerationOutcomesUseCase(
                outcomesClient: client,
                accessTokenProvider: StubTokenProvider(token: "access")
            ),
            personalRuleReceiptStore: store
        )
        await viewModel.refreshCatalogSources()
        #expect(viewModel.failedGenerationOutcomes.count == 1)

        await viewModel.deleteFailedGenerationOutcome(jobID: Self.failedOutcome.jobID)

        #expect(viewModel.failedGenerationOutcomes.isEmpty)
        #expect(store.hiddenIDs(userID: viewModel.currentUserID).contains(Self.failedOutcome.jobID.uuidString))

        // 中文注释：再次刷新，隐藏仍然生效（来自 store）。
        await viewModel.refreshCatalogSources()
        #expect(viewModel.failedGenerationOutcomes.isEmpty)
    }

    @Test func expiredReceiptHidesThePersonalRuleOnRefresh() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let store: InMemoryReceiptStore = InMemoryReceiptStore()
        let userID: String = "expiry-user"
        let now: Date = Date(timeIntervalSince1970: 1_800_000_000)
        // 中文注释：目录来自 StubPageDataLoader，为空；这里只验证到期回执会被隐藏并清理。
        store.receiptsByUser["expiry"] = [:]
        let viewModel: SourcesViewModel = Harness.makeSourcesViewModel(
            database: database,
            resolver: Harness.resolver(),
            personalRuleReceiptStore: store,
            now: { now }
        )
        store.recordReceiptIfAbsent(catalogSourceID: "old-rule", userID: viewModel.currentUserID, receivedAt: now.addingTimeInterval(-8 * 24 * 3600))
        store.recordReceiptIfAbsent(catalogSourceID: "fresh-rule", userID: viewModel.currentUserID, receivedAt: now.addingTimeInterval(-3600))
        _ = userID

        await viewModel.refreshCatalogSources()

        #expect(viewModel.hiddenPersonalRuleIDs.contains("old-rule"))
        #expect(viewModel.hiddenPersonalRuleIDs.contains("fresh-rule") == false)
        #expect(viewModel.personalRuleReceipts["fresh-rule"] != nil)
        let remaining: (days: Int, hours: Int) = viewModel.personalRuleRemainingComponents(
            for: CatalogSource(id: "fresh-rule", name: "f", baseURL: "https://f.invalid", kind: .video, ruleJSON: "{}")
        )
        #expect(remaining.days == 6 && remaining.hours == 23)
    }

    @Test func outcomeTextFallsBackForUnknownValues() {
        let unknown: VideoGenerationOutcome = VideoGenerationOutcome(
            jobID: UUID(), entryURL: nil, status: "failed", finishedAt: nil,
            catalogSourceID: nil, reason: "brandNewReason", reasonDetail: "brandNewDetail"
        )
        #expect(
            VideoGenerationOutcomeText.reasonText(for: unknown)
                == NSLocalizedString("video_generation_outcome_failed_unknown", comment: "")
        )
        #expect(VideoGenerationOutcomeText.reasonDetailText(for: unknown) == nil)
        #expect(
            VideoGenerationOutcomeText.reasonDetailText(for: Self.failedOutcome)
                == NSLocalizedString("video_generation_outcome_detail_episodeLayoutUnsupported", comment: "")
        )
    }
}
