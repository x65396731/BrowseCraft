import BrowseCraftDomain
import BrowseCraftLog
import Foundation

// 中文注释：问题报告的失败快照（docs/design/Problem-Report-Design.md 第六节「失败快照」组，`BCA-OBS-020`）。
// 只由 `RuleFailureDiagnostics.report` 在上报之后写入，只在内存里、不落盘；各页不自行收集。
// 取自 `RuleExecutionError` 的 case 与关联值，不含网址与网页源码（`BCA-OBS-019`）。

/// 中文注释：一次规则执行失败的可报告摘要。`stage` 与 `kind` 存原始值，避免把非 Sendable 的枚举带进并发上下文。
struct RuleFailureSnapshot: Hashable, Sendable {
    let point: RuleFailurePoint
    let stage: String
    let kind: String
    let sourceID: String?
    /// `RuleExecutionError` 的 case 名；不是规则错误时为 nil。
    let errorCase: String?
    let statusCode: Int?
    let ruleID: String?
    let operation: String?
    let selector: String?
    /// `ErrorDiagnostics.summary` 的脱敏摘要。
    let summary: String
    let occurredAt: Date

    init(
        error: any Error,
        kind: DiagnosticFailureKind,
        stage: DiagnosticRuleStage,
        point: RuleFailurePoint,
        sourceID: String?,
        occurredAt: Date = Date()
    ) {
        self.point = point
        self.stage = stage.rawValue
        self.kind = kind.rawValue
        self.sourceID = sourceID
        self.summary = ErrorDiagnostics.summary(for: error)
        self.occurredAt = occurredAt
        guard let ruleError: RuleExecutionError = error as? RuleExecutionError else {
            self.errorCase = nil
            self.statusCode = nil
            self.ruleID = nil
            self.operation = nil
            self.selector = nil
            return
        }
        self.errorCase = ruleError.caseName
        switch ruleError {
        case .httpStatus(_, let statusCode):
            self.statusCode = statusCode
            self.ruleID = nil
            self.operation = nil
            self.selector = nil
        case .selectorEmpty(_, _, _, let ruleID):
            self.statusCode = nil
            self.ruleID = ruleID
            self.operation = nil
            self.selector = nil
        case .parserDiagnostics(_, _, let ruleID, _, let operation, let selector, _, _):
            self.statusCode = nil
            self.ruleID = ruleID
            self.operation = operation
            self.selector = selector
        case .network, .antiBot, .accessRequired, .ruleConfiguration, .responseContract,
             .apiResponseContract, .sourceAPI, .protectedResource, .unknown:
            self.statusCode = nil
            self.ruleID = nil
            self.operation = nil
            self.selector = nil
        }
    }

    /// 中文注释：面板上「看起来是网站暂时打不开或要登录」那行灰字的判据（合同第四节「站点侧提示」）：
    /// 网络失败、反爬页、HTTP 429 / 5xx、需要账号。
    var looksSiteSide: Bool {
        switch self.errorCase {
        case "network", "antiBot", "accessRequired":
            return true
        case "httpStatus":
            guard let statusCode: Int = self.statusCode else {
                return false
            }
            return statusCode == 429 || statusCode >= 500
        default:
            return false
        }
    }
}

extension RuleExecutionError {
    /// 中文注释：case 名，与 PortalCore 站点侧判定（`network`、`antiBot`、`httpStatus`）同一口径。
    var caseName: String {
        switch self {
        case .network:
            return "network"
        case .antiBot:
            return "antiBot"
        case .httpStatus:
            return "httpStatus"
        case .accessRequired:
            return "accessRequired"
        case .selectorEmpty:
            return "selectorEmpty"
        case .ruleConfiguration:
            return "ruleConfiguration"
        case .responseContract:
            return "responseContract"
        case .apiResponseContract:
            return "apiResponseContract"
        case .sourceAPI:
            return "sourceAPI"
        case .protectedResource:
            return "protectedResource"
        case .parserDiagnostics:
            return "parserDiagnostics"
        case .unknown:
            return "unknown"
        }
    }
}

/// 中文注释：本次启动内最近的失败快照，最多 20 条；按（失败点，来源 ID）取最近一条。
/// `@unchecked` 的依据（architecture.md 第 4 节）：`snapshots` 只在 `lock` 内读写。
final class RuleFailureSnapshotStore: @unchecked Sendable {
    static let shared: RuleFailureSnapshotStore = RuleFailureSnapshotStore()
    static let capacity: Int = 20

    private let lock: NSLock = NSLock()
    private var snapshots: [RuleFailureSnapshot] = []

    func record(_ snapshot: RuleFailureSnapshot) {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.snapshots.append(snapshot)
        if self.snapshots.count > Self.capacity {
            self.snapshots.removeFirst(self.snapshots.count - Self.capacity)
        }
    }

    /// 中文注释：这些失败点里、属于该来源的最近一条；没有时为 nil。
    func latest(points: Set<RuleFailurePoint>, sourceID: String) -> RuleFailureSnapshot? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.snapshots.last { snapshot in
            return points.contains(snapshot.point) && snapshot.sourceID == sourceID
        }
    }
}
