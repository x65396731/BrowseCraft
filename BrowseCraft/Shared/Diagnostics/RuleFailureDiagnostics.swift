import BrowseCraftDomain
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
        AppAnalytics.shared.logDiagnosticFailure(kind: kind, stage: stage, point: point, source: source)
        CrashDiagnostics.shared.recordRuleFailure(error: error, kind: kind, stage: stage, point: point, source: source)
    }
}
