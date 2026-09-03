import Foundation

/// 后端已受理的规则生成任务回执（`202`）。
struct VideoGenerationTaskReceipt: Hashable, Sendable {
    let jobID: UUID
    let submittedEntryURL: String
}

/// 任务创建的 typed 结果（`BC-PREFLIGHT-046`）。
enum VideoGenerationTaskSubmissionOutcome: Hashable, Sendable {
    case submitted(VideoGenerationTaskReceipt)
    case authRequired
    case activeJobLimit
    case failed(code: String)
}

/// 用例入口的 typed 拒绝：不满足 `canSubmit` 或版本漂移的结果不得到达客户端（`BC-PREFLIGHT-047`）。
enum VideoGenerationTaskSubmissionRejection: Error, Hashable, Sendable {
    case preflightNotAccepted(VideoGenerationInputPreflightStatus)
    case preflightPolicyDrift(schemaVersion: Int, generatorPolicyVersion: String)
}
