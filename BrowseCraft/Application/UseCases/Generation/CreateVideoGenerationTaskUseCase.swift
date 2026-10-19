import BrowseCraftDomain
import BrowseCraftLog
import Foundation

/// 预检 accepted → 创建生成任务（独立于 `AssessVideoGenerationInputUseCase`，`BC-PREFLIGHT-048`）。
struct CreateVideoGenerationTaskUseCase: Sendable {
    /// 服务端复用规则无法按 Catalog 路径解密/落地时的稳定失败码（`BC-PREFLIGHT-055`）。
    static let reusedRuleDecryptionFailedCode: String = "REUSED_RULE_DECRYPTION_FAILED"
    static let reusedRuleKindUnsupportedCode: String = "REUSED_RULE_KIND_UNSUPPORTED"

    private let taskClient: any VideoGenerationTaskCreating
    private let accessTokenProvider: any PortalAccessTokenProviding
    private let catalogRuleDecryptor: CatalogRuleDecryptor
    /// 提交前的只读预览（Generation-Input-Page-Redesign-Design.md 第三节）；nil = 未接线，输入页按「没有现成规则」显示。
    private let reusePreviewer: (any GenerationReusePreviewing)?

    init(
        taskClient: any VideoGenerationTaskCreating,
        accessTokenProvider: any PortalAccessTokenProviding,
        catalogRuleDecryptor: CatalogRuleDecryptor = CatalogRuleDecryptor(),
        reusePreviewer: (any GenerationReusePreviewing)? = nil
    ) {
        self.taskClient = taskClient
        self.accessTokenProvider = accessTokenProvider
        self.catalogRuleDecryptor = catalogRuleDecryptor
        self.reusePreviewer = reusePreviewer
    }

    /// 检查可提交后问一次：这个网址此刻提交会不会直接取用现成规则、要多少 coin。
    ///
    /// 中文注释：与 `execute` 用同一个提交串（`submissionString`），服务端走同一个复用判定。未登录、未接线、
    /// 不可取用与查询失败一律返回 nil——输入页照常显示取页方式与「滑动生成」，不弹错；失败记一条吞错日志（`BCA-OBS-015`）。
    func reusePreview(
        preflight: VideoGenerationInputPreflight,
        sourceKind: RuleGenerationSourceKind
    ) async -> GenerationReusePreview? {
        guard preflight.canSubmit,
              let previewer: any GenerationReusePreviewing = self.reusePreviewer,
              let accessToken: String = await self.accessTokenProvider.validAccessToken() else {
            return nil
        }
        do {
            return try await previewer.reusePreview(
                sourceKind: sourceKind,
                entryURL: preflight.submissionString,
                accessToken: accessToken
            )
        } catch is CancellationError {
            return nil
        } catch {
            AppLog.error(.generation, "reuse-preview-unavailable", [
                "kind": .enumValue(sourceKind),
                "error": .error(error)
            ])
            return nil
        }
    }

    /// 只接受 `canSubmit == true` 且版本未漂移的预检结果；提交串只取 `submissionString`。
    ///
    /// 中文注释：预检本身是中性的（只看列表族数量、发布组、截断与反爬登录，无任何视频
    /// 语义词），因此两种 kind 共用同一份 accepted 结果；`sourceKind` 只决定提交给
    /// 服务端的生成链，不参与预检判定。
    func execute(
        preflight: VideoGenerationInputPreflight,
        sourceKind: RuleGenerationSourceKind,
        refresh: Bool = false,
        acquisitionTier: GenerationAcquisitionTier = .normal
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
                sourceKind: sourceKind,
                entryURL: preflight.submissionString,
                refresh: refresh,
                acquisitionTier: acquisitionTier,
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
            case .insufficientCoins(let balance, let required):
                return .insufficientCoins(balance: balance, required: required)
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
            AppLog.error(.generation, "reused-rule-decrypt-failed", ["error": .error(error)])
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
                    ruleJSON: ruleJSON,
                    catalogRevision: stored.catalogRevision
                ),
                coinCharged: stored.coinCharged,
                coinBalance: stored.coinBalance,
                coinRevision: stored.coinRevision
            )
        )
    }
}
