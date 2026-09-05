import BrowseCraftDomain
import CryptoKit
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
        private let result: Result<VideoGenerationTaskCreation, VideoGenerationTaskClientError>

        init(result: Result<UUID, VideoGenerationTaskClientError>) {
            switch result {
            case .success(let jobID):
                self.result = .success(
                    .queued(
                        VideoGenerationTaskReceipt(
                            jobID: jobID,
                            submittedEntryURL: CreateVideoGenerationTaskUseCaseTests.watchURL
                        )
                    )
                )
            case .failure(let error):
                self.result = .failure(error)
            }
        }

        init(reused: VideoGenerationReusedCatalogSource) {
            self.result = .success(.reused(reused))
        }

        func createVideoTask(
            entryURL: String,
            accessToken: String
        ) async throws -> VideoGenerationTaskCreation {
            self.calls.append(Call(entryURL: entryURL, accessToken: accessToken))
            return try self.result.get()
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
            entryShape: status == .accepted ? .directListOwner : .ambiguous,
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
            (.previousJobActive(entryURL: "https://gimy.tv/browse/1.html"),
             .previousJobActive(entryURL: "https://gimy.tv/browse/1.html")),
            (.rateLimited, .rateLimited),
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

    // MARK: - `BC-PREFLIGHT-055` 服务端复用规则

    private static let catalogKey: SymmetricKey = SymmetricKey(size: .bits256)

    /// 用与 PortalCore 相同的 AES-256-GCM 形态（nonce + ciphertext‖tag）封装一条 catalog payload。
    private func encryptedRule(payload: [String: Any]) throws -> EncryptedCatalogRule {
        let plaintext: Data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let nonce: AES.GCM.Nonce = AES.GCM.Nonce()
        let sealed: AES.GCM.SealedBox = try AES.GCM.seal(plaintext, using: Self.catalogKey, nonce: nonce)
        return EncryptedCatalogRule(
            version: 1,
            keyId: "test-key",
            nonce: Data(nonce).base64EncodedString(),
            ciphertext: (sealed.ciphertext + sealed.tag).base64EncodedString()
        )
    }

    private func decryptor() -> CatalogRuleDecryptor {
        return CatalogRuleDecryptor(
            keyProvider: CatalogRuleDecryptionKeyProvider(keysByID: ["test-key": Self.catalogKey])
        )
    }

    func testReusedRuleIsDecryptedThroughTheCatalogPathAndNotResubmitted() async throws {
        let rule: EncryptedCatalogRule = try self.encryptedRule(payload: [
            "id": "catalog.video.example",
            "name": "Example",
            "baseURL": "https://example.invalid",
            "kind": "video",
            "ruleJSON": ["site": ["baseURL": "https://example.invalid"]]
        ])
        let client = RecordingTaskClient(
            reused: VideoGenerationReusedCatalogSource(
                catalogSourceID: "catalog.video.example",
                entryURL: Self.watchURL,
                name: "Example",
                baseURL: "https://example.invalid",
                kind: "video",
                encryptedRule: rule
            )
        )
        let useCase = CreateVideoGenerationTaskUseCase(
            taskClient: client,
            accessTokenProvider: StaticTokenProvider(token: "access-1"),
            catalogRuleDecryptor: self.decryptor()
        )

        let outcome = try await useCase.execute(preflight: self.preflight(status: .accepted))

        guard case .reused(let reused) = outcome else {
            return XCTFail("expected reused outcome, got \(outcome)")
        }
        XCTAssertEqual(reused.catalogSourceID, "catalog.video.example")
        XCTAssertEqual(reused.entryURL, Self.watchURL)
        XCTAssertEqual(reused.catalogSource.id, "catalog.video.example")
        XCTAssertEqual(reused.catalogSource.kind, .video)
        XCTAssertEqual(reused.catalogSource.baseURL, "https://example.invalid")
        // 中文注释：与 LoadCatalogSourcesUseCase 一样只取内层 ruleJSON（importRuleJSON）。
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(reused.catalogSource.ruleJSON.utf8)) as? [String: Any]
        )
        XCTAssertEqual(Set(object.keys), ["site"])
        // 不得再以 refresh 重发：客户端恰好被调用一次。
        let calls = await client.recordedCalls()
        XCTAssertEqual(calls.count, 1)
    }

    func testReusedRuleWithUnknownKeyIsATypedFailure() async throws {
        let rule: EncryptedCatalogRule = try self.encryptedRule(payload: ["id": "x"])
        let client = RecordingTaskClient(
            reused: VideoGenerationReusedCatalogSource(
                catalogSourceID: "catalog.video.example",
                entryURL: Self.watchURL,
                name: "Example",
                baseURL: "https://example.invalid",
                kind: "video",
                encryptedRule: rule
            )
        )
        let useCase = CreateVideoGenerationTaskUseCase(
            taskClient: client,
            accessTokenProvider: StaticTokenProvider(token: "access-1"),
            catalogRuleDecryptor: CatalogRuleDecryptor(
                keyProvider: CatalogRuleDecryptionKeyProvider(keysByID: [:])
            )
        )

        let outcome = try await useCase.execute(preflight: self.preflight(status: .accepted))

        XCTAssertEqual(
            outcome,
            .failed(code: CreateVideoGenerationTaskUseCase.reusedRuleDecryptionFailedCode)
        )
    }
}
