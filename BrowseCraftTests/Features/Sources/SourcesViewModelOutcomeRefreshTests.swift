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
        private(set) var hiddenJobIDs: [UUID] = []
        private var outcomes: [VideoGenerationOutcome]

        init(outcomes: [VideoGenerationOutcome]) {
            self.outcomes = outcomes
        }

        func fetchOutcomes(accessToken: String) async throws -> [VideoGenerationOutcome] {
            self.callCount += 1
            return self.outcomes
        }

        /// 中文注释：模拟服务端软删除——之后的读取不再返回该条。
        func hideOutcome(jobID: UUID, accessToken: String) async throws {
            self.hiddenJobIDs.append(jobID)
            self.outcomes.removeAll { $0.jobID == jobID }
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

    @Test func deletingAFailedOutcomeHidesItOnTheServerAndReloads() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let client: ScriptedOutcomesClient = ScriptedOutcomesClient(outcomes: [Self.failedOutcome])
        let tokens: StubTokenProvider = StubTokenProvider(token: "access")
        let viewModel: SourcesViewModel = Harness.makeSourcesViewModel(
            database: database,
            resolver: Harness.resolver(),
            loadVideoGenerationOutcomesUseCase: LoadVideoGenerationOutcomesUseCase(outcomesClient: client, accessTokenProvider: tokens),
            hideVideoGenerationOutcomeUseCase: HideVideoGenerationOutcomeUseCase(outcomesClient: client, accessTokenProvider: tokens)
        )
        await viewModel.refreshCatalogSources()
        #expect(viewModel.failedGenerationOutcomes.count == 1)

        await viewModel.deleteFailedGenerationOutcome(jobID: Self.failedOutcome.jobID)

        #expect(await client.hiddenJobIDs == [Self.failedOutcome.jobID])
        #expect(viewModel.failedGenerationOutcomes.isEmpty)
        // 中文注释：Harness 的目录加载器是 stub，会留下目录刷新错误；删除本身不能再叠加错误。
        #expect(viewModel.errorMessage != NSLocalizedString("rule_error_unknown", comment: ""))
    }

    @Test func remainingTimeComesFromServerExpiresAt() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let now: Date = Date(timeIntervalSince1970: 1_800_000_000)
        let mine: CatalogSource = CatalogSource(id: "mine", name: "mine", baseURL: "https://m.invalid", kind: .video, ruleJSON: "{}")
        var succeeded: VideoGenerationOutcome = VideoGenerationOutcome(
            jobID: UUID(), entryURL: "https://m.invalid/list", status: "succeeded", finishedAt: nil,
            catalogSourceID: "mine", reason: nil, reasonDetail: nil
        )
        succeeded.expiresAt = now.addingTimeInterval(6 * 24 * 3600 + 23 * 3600)
        succeeded.catalogSource = mine
        let client: ScriptedOutcomesClient = ScriptedOutcomesClient(outcomes: [succeeded])
        let viewModel: SourcesViewModel = Harness.makeSourcesViewModel(
            database: database,
            resolver: Harness.resolver(),
            loadVideoGenerationOutcomesUseCase: LoadVideoGenerationOutcomesUseCase(outcomesClient: client, accessTokenProvider: StubTokenProvider(token: "access")),
            now: { now }
        )

        await viewModel.refreshCatalogSources()

        #expect(viewModel.personalCatalogSources == [mine])
        let remaining: (days: Int, hours: Int)? = viewModel.personalRuleRemainingComponents(for: mine)
        #expect(remaining?.days == 6 && remaining?.hours == 23)
        #expect(viewModel.personalRuleEntryURL(for: mine) == "https://m.invalid/list")
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
