import BrowseCraftDomain
import Foundation

/// 后端已受理的规则生成任务回执（`202`）。
struct VideoGenerationTaskReceipt: Hashable, Sendable {
    let jobID: UUID
    let submittedEntryURL: String
}

/// 服务端直接返回的已生成规则（`200 cached`，`BC-PREFLIGHT-055`）：仍是密文，由用例走 Catalog 同一解密路径。
struct VideoGenerationReusedCatalogSource: Hashable, Sendable {
    let catalogSourceID: String
    let entryURL: String
    let name: String
    let baseURL: String
    let kind: String
    let encryptedRule: EncryptedCatalogRule
}

/// 任务客户端的两种成功结果：已排队，或复用库中规则。
enum VideoGenerationTaskCreation: Hashable, Sendable {
    case queued(VideoGenerationTaskReceipt)
    case reused(VideoGenerationReusedCatalogSource)
}

/// 已解密、可直接走 `AddCatalogSourceUseCase` 的复用规则。
struct VideoGenerationReusedRule: Hashable, Sendable {
    let catalogSourceID: String
    let entryURL: String
    let catalogSource: CatalogSource
}

/// 任务创建的 typed 结果（`BC-PREFLIGHT-046`）。
enum VideoGenerationTaskSubmissionOutcome: Hashable, Sendable {
    case submitted(VideoGenerationTaskReceipt)
    case reused(VideoGenerationReusedRule)
    case authRequired
    case activeJobLimit
    case previousJobActive(entryURL: String?)
    case rateLimited
    case failed(code: String)
}

/// 用例入口的 typed 拒绝：不满足 `canSubmit` 或版本漂移的结果不得到达客户端（`BC-PREFLIGHT-047`）。
enum VideoGenerationTaskSubmissionRejection: Error, Hashable, Sendable {
    case preflightNotAccepted(VideoGenerationInputPreflightStatus)
    case preflightPolicyDrift(schemaVersion: Int, generatorPolicyVersion: String)
}
