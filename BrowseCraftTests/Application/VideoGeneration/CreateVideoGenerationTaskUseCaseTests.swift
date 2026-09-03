import Foundation
import XCTest
@testable import BrowseCraft

/// `BC-PREFLIGHT-045/046/047` 特征化：凭据、typed 结果、canSubmit 门控与提交串不变。
final class CreateVideoGenerationTaskUseCaseTests: XCTestCase {
    private actor RecordingTaskClient: VideoGenerationTaskCreating {
        struct Call: Equatable {
            let entryURL: String
            let accessToken: String
        }

        private(set) var calls: [Call] = []
        private let result: Result<UUID, VideoGenerationTaskClientError>

        init(result: Result<UUID, VideoGenerationTaskClientError>) {
            self.result = result
        }

        func createVideoTask(
            entryURL: String,
            accessToken: String
        ) async throws -> VideoGenerationTaskReceipt {
            self.calls.append(Call(entryURL: entryURL, accessToken: accessToken))
            return VideoGenerationTaskReceipt(
                jobID: try self.result.get(),
                submittedEntryURL: entryURL
            )
        }

        func recordedCalls() -> [Call] {
            return self.calls
        }
    }

    private struct StaticTokenProvider: PortalAccessTokenProviding {
        let token: String?

        func validAccessToken() async -> String? {
            return self.token
        }
    }

    private static let watchURL: String = "https://91porn.com/v.php?next=watch"

    private func preflight(
        status: VideoGenerationInputPreflightStatus,
        submission: String = CreateVideoGenerationTaskUseCaseTests.watchURL
    ) -> VideoGenerationInputPreflight {
        return VideoGenerationInputPreflight(
            status: status,
            reason: status == .accepted ? nil : .entryShapeAmbiguous,
            evaluatedInputURL: URL(string: submission)!,
            submissionString: submission,
            entryShape: .directListOwner,
            familyCoverageState: status == .accepted ? .oneFamilyCoversAll : .unresolved,
            audit: VideoGenerationInputPreflightAudit()
        )
    }

    func testAcceptedSubmitsExactSubmissionStringWithBearerToken() async throws {
        let jobID: UUID = UUID()
        let client = RecordingTaskClient(result: .success(jobID))
        let useCase = CreateVideoGenerationTaskUseCase(
            taskClient: client,
            accessTokenProvider: StaticTokenProvider(token: "access-1")
        )

        let outcome = try await useCase.execute(preflight: self.preflight(status: .accepted))

        XCTAssertEqual(
            outcome,
            .submitted(VideoGenerationTaskReceipt(jobID: jobID, submittedEntryURL: Self.watchURL))
        )
        let calls = await client.recordedCalls()
        XCTAssertEqual(calls, [.init(entryURL: Self.watchURL, accessToken: "access-1")])
    }

    func testRejectedAndInconclusiveNeverReachTheClient() async {
        for status: VideoGenerationInputPreflightStatus in [.rejected, .inconclusive] {
            let client = RecordingTaskClient(result: .success(UUID()))
            let useCase = CreateVideoGenerationTaskUseCase(
                taskClient: client,
                accessTokenProvider: StaticTokenProvider(token: "access-1")
            )
            do {
                _ = try await useCase.execute(preflight: self.preflight(status: status))
                XCTFail("\(status) must be rejected before the client")
            } catch let rejection as VideoGenerationTaskSubmissionRejection {
                XCTAssertEqual(rejection, .preflightNotAccepted(status))
            } catch {
                XCTFail("unexpected error \(error)")
            }
            let calls = await client.recordedCalls()
            XCTAssertTrue(calls.isEmpty)
        }
    }

    func testMissingSessionReturnsAuthRequiredWithoutCallingClient() async throws {
        let client = RecordingTaskClient(result: .success(UUID()))
        let useCase = CreateVideoGenerationTaskUseCase(
            taskClient: client,
            accessTokenProvider: StaticTokenProvider(token: nil)
        )

        let outcome = try await useCase.execute(preflight: self.preflight(status: .accepted))

        XCTAssertEqual(outcome, .authRequired)
        let calls = await client.recordedCalls()
        XCTAssertTrue(calls.isEmpty)
    }

    func testClientErrorsMapToTypedOutcomes() async throws {
        let expectations: [(VideoGenerationTaskClientError, VideoGenerationTaskSubmissionOutcome)] = [
            (.activeJobLimit, .activeJobLimit),
            (.authRequired, .authRequired),
            (.server(code: "RULE_GENERATION_PERSISTENCE_ERROR"),
             .failed(code: "RULE_GENERATION_PERSISTENCE_ERROR")),
            (.transport, .failed(code: "transport"))
        ]
        for (error, expected) in expectations {
            let useCase = CreateVideoGenerationTaskUseCase(
                taskClient: RecordingTaskClient(result: .failure(error)),
                accessTokenProvider: StaticTokenProvider(token: "access-1")
            )
            let outcome = try await useCase.execute(preflight: self.preflight(status: .accepted))
            XCTAssertEqual(outcome, expected)
        }
    }
}
