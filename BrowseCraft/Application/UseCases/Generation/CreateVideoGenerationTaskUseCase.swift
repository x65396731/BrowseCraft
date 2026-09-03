import Foundation

/// 预检 accepted → 创建生成任务（独立于 `AssessVideoGenerationInputUseCase`，`BC-PREFLIGHT-048`）。
struct CreateVideoGenerationTaskUseCase: Sendable {
    private let taskClient: any VideoGenerationTaskCreating
    private let accessTokenProvider: any PortalAccessTokenProviding

    init(
        taskClient: any VideoGenerationTaskCreating,
        accessTokenProvider: any PortalAccessTokenProviding
    ) {
        self.taskClient = taskClient
        self.accessTokenProvider = accessTokenProvider
    }

    /// 只接受 `canSubmit == true` 且版本未漂移的预检结果；提交串只取 `submissionString`。
    func execute(
        preflight: VideoGenerationInputPreflight
    ) async throws -> VideoGenerationTaskSubmissionOutcome {
        guard preflight.canSubmit else {
            throw VideoGenerationTaskSubmissionRejection.preflightNotAccepted(preflight.status)
        }
        guard preflight.schemaVersion == VideoGenerationInputPreflight.currentSchemaVersion,
              preflight.generatorPolicyVersion
                == VideoGenerationInputPreflight.currentGeneratorPolicyVersion else {
            throw VideoGenerationTaskSubmissionRejection.preflightPolicyDrift(
                schemaVersion: preflight.schemaVersion,
                generatorPolicyVersion: preflight.generatorPolicyVersion
            )
        }
        guard let accessToken: String = await self.accessTokenProvider.validAccessToken() else {
            return .authRequired
        }
        do {
            let receipt: VideoGenerationTaskReceipt = try await self.taskClient.createVideoTask(
                entryURL: preflight.submissionString,
                accessToken: accessToken
            )
            return .submitted(receipt)
        } catch let error as VideoGenerationTaskClientError {
            switch error {
            case .authRequired:
                return .authRequired
            case .activeJobLimit:
                return .activeJobLimit
            case .server(let code):
                return .failed(code: code)
            case .transport:
                return .failed(code: "transport")
            }
        }
    }
}
