import Foundation
import Testing
@testable import BrowseCraft

struct LoadVideoGenerationOutcomesUseCaseTests {
    private struct StubTokenProvider: PortalAccessTokenProviding {
        let token: String?
        func validAccessToken() async -> String? { return self.token }
    }

    private actor SpyOutcomesClient: VideoGenerationOutcomesFetching {
        private(set) var accessTokens: [String] = []
        private let result: Result<[VideoGenerationOutcome], any Error>

        init(result: Result<[VideoGenerationOutcome], any Error>) {
            self.result = result
        }

        func fetchOutcomes(accessToken: String) async throws -> [VideoGenerationOutcome] {
            self.accessTokens.append(accessToken)
            return try self.result.get()
        }
    }

    private static let outcome: VideoGenerationOutcome = VideoGenerationOutcome(
        jobID: UUID(),
        entryURL: "https://example.invalid/list",
        status: "succeeded",
        finishedAt: nil,
        catalogSourceID: "example-invalid",
        reason: nil,
        reasonDetail: nil
    )

    @Test func withoutSessionReturnsAuthRequiredWithoutCallingTheClient() async {
        let client: SpyOutcomesClient = SpyOutcomesClient(result: .success([Self.outcome]))
        let useCase: LoadVideoGenerationOutcomesUseCase = LoadVideoGenerationOutcomesUseCase(
            outcomesClient: client,
            accessTokenProvider: StubTokenProvider(token: nil)
        )

        let load: VideoGenerationOutcomesLoad = await useCase.execute()

        #expect(load == .authRequired)
        #expect(await client.accessTokens.isEmpty)
    }

    @Test func withSessionPassesTheTokenAndReturnsOutcomes() async {
        let client: SpyOutcomesClient = SpyOutcomesClient(result: .success([Self.outcome]))
        let useCase: LoadVideoGenerationOutcomesUseCase = LoadVideoGenerationOutcomesUseCase(
            outcomesClient: client,
            accessTokenProvider: StubTokenProvider(token: "access")
        )

        let load: VideoGenerationOutcomesLoad = await useCase.execute()

        #expect(load == .loaded([Self.outcome]))
        #expect(await client.accessTokens == ["access"])
    }

    @Test func clientAuthFailureBecomesAuthRequiredAndServerFailureKeepsItsCode() async {
        let unauthorized: LoadVideoGenerationOutcomesUseCase = LoadVideoGenerationOutcomesUseCase(
            outcomesClient: SpyOutcomesClient(
                result: .failure(VideoGenerationOutcomesClientError.authRequired)
            ),
            accessTokenProvider: StubTokenProvider(token: "stale")
        )
        let failing: LoadVideoGenerationOutcomesUseCase = LoadVideoGenerationOutcomesUseCase(
            outcomesClient: SpyOutcomesClient(
                result: .failure(VideoGenerationOutcomesClientError.server(code: "RULE_GENERATION_PERSISTENCE_ERROR"))
            ),
            accessTokenProvider: StubTokenProvider(token: "access")
        )

        #expect(await unauthorized.execute() == .authRequired)
        #expect(await failing.execute() == .failed(code: "RULE_GENERATION_PERSISTENCE_ERROR"))
    }
}
