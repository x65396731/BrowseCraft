import BrowseCraftDomain
import Foundation

/// 预检 accepted → 创建生成任务（独立于 `AssessVideoGenerationInputUseCase`，`BC-PREFLIGHT-048`）。
struct CreateVideoGenerationTaskUseCase: Sendable {
    /// 服务端复用规则无法按 Catalog 路径解密/落地时的稳定失败码（`BC-PREFLIGHT-055`）。
    static let reusedRuleDecryptionFailedCode: String = "REUSED_RULE_DECRYPTION_FAILED"
    static let reusedRuleKindUnsupportedCode: String = "REUSED_RULE_KIND_UNSUPPORTED"

    private let taskClient: any VideoGenerationTaskCreating
    private let accessTokenProvider: any PortalAccessTokenProviding
    private let catalogRuleDecryptor: CatalogRuleDecryptor

    init(
        taskClient: any VideoGenerationTaskCreating,
        accessTokenProvider: any PortalAccessTokenProviding,
        catalogRuleDecryptor: CatalogRuleDecryptor = CatalogRuleDecryptor()
    ) {
        self.taskClient = taskClient
        self.accessTokenProvider = accessTokenProvider
        self.catalogRuleDecryptor = catalogRuleDecryptor
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
            let creation: VideoGenerationTaskCreation = try await self.taskClient.createVideoTask(
                entryURL: preflight.submissionString,
                accessToken: accessToken
            )
            switch creation {
            case .queued(let receipt):
                return .submitted(receipt)
            case .reused(let stored):
                return self.reusedOutcome(stored)
            }
        } catch let error as VideoGenerationTaskClientError {
            switch error {
            case .authRequired:
                return .authRequired
            case .activeJobLimit:
                return .activeJobLimit
            case .previousJobActive(let entryURL):
                return .previousJobActive(entryURL: entryURL)
            case .rateLimited:
                return .rateLimited
            case .server(let code):
                return .failed(code: code)
            case .transport:
                return .failed(code: "transport")
            }
        }
    }

    /// 中文注释：与 `LoadCatalogSourcesUseCase` 走同一解密器与 `importRuleJSON` 规则，不另起解析分支（`BC-PREFLIGHT-055`）。
    private func reusedOutcome(
        _ stored: VideoGenerationReusedCatalogSource
    ) -> VideoGenerationTaskSubmissionOutcome {
        guard let kind: CatalogSourceKind = CatalogSourceKind(rawValue: stored.kind) else {
            return .failed(code: Self.reusedRuleKindUnsupportedCode)
        }
        let ruleJSON: String
        do {
            let decrypted: CatalogRuleJSONValue = try self.catalogRuleDecryptor.decrypt(stored.encryptedRule)
            let data: Data = try JSONEncoder().encode(decrypted.importRuleJSON)
            ruleJSON = String(decoding: data, as: UTF8.self)
        } catch {
            return .failed(code: Self.reusedRuleDecryptionFailedCode)
        }
        return .reused(
            VideoGenerationReusedRule(
                catalogSourceID: stored.catalogSourceID,
                entryURL: stored.entryURL,
                catalogSource: CatalogSource(
                    id: stored.catalogSourceID,
                    name: stored.name,
                    baseURL: stored.baseURL,
                    kind: kind,
                    ruleJSON: ruleJSON
                )
            )
        )
    }
}
