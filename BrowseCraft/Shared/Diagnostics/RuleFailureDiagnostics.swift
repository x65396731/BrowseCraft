import BrowseCraftDomain
import BrowseCraftLog
import Foundation

// 中文注释：规则执行失败的唯一上报入口（BCA-OBS-007）。一次调用同时发 I 组的诊断事件和一条 Crashlytics 非致命错误，
// 两边按同一个失败点一一对应，不会出现 Analytics 有、Crashlytics 漏记的失败点。
// 类别判定由 Application 的 `RuleExecutionErrorClassifier` 完成后传进来——Shared 不得反向引用它的错误类型。

enum RuleFailureDiagnostics {
    static func report(
        error: any Error,
        kind: DiagnosticFailureKind,
        stage: DiagnosticRuleStage,
        point: RuleFailurePoint,
        source: Source?
    ) {
        // 中文注释：用户取消与被新请求取代的请求不算失败，I 组事件与非致命错误都不记（埋点合同第 6.1 节）。
        // 2026-10-18 在 Crashlytics 控制台看到：影视详情加载被取消时报成 Swift.CancellationError，30 天 23 次，是最大的一个非致命问题。
        // 在这个唯一入口统一挡掉，不靠每个调用点各自先接住 CancellationError。
        if Self.isCancellation(error) {
            AppLog.info(.rule, "rule-cancelled", ["point": .enumValue(point), "stage": .enumValue(stage)])
            return
        }
        AppLog.error(.rule, "rule-failure", [
            "point": .enumValue(point),
            "kind": .enumValue(kind),
            "stage": .enumValue(stage),
            "source": .id(source?.id),
            "error": .error(error)
        ])
        AppAnalytics.shared.logDiagnosticFailure(kind: kind, stage: stage, point: point, source: source)
        CrashDiagnostics.shared.recordRuleFailure(error: error, kind: kind, stage: stage, point: point, source: source)
    }

    static func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError || Task.isCancelled {
            return true
        }
        return (error as? URLError)?.code == .cancelled
    }
}
