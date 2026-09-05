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

        requests.request()

        let refreshed: Bool = await Harness.waitUntil {
            viewModel.failedGenerationOutcomes.count == 1
        }
        #expect(refreshed)
        #expect(viewModel.failedGenerationOutcomes.first?.reasonDetail == "episodeLayoutUnsupported")
        #expect(viewModel.personalCatalogSources.isEmpty)
        #expect(viewModel.isPersonalCatalogSignInRequired == false)
        #expect(await client.callCount == 1)
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
