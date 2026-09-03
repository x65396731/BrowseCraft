import Foundation

// 中文注释：RuleExecutionLogger 统一规则执行链路的调试日志格式，便于回归时快速定位断点。
// 它随规则执行代码留在内核，输出经 RuleRuntimeDebugLog 的 sink 汇入 App 的日志实现。

/// 中文注释：Debug 环境下记录列表、详情、阅读页和图片请求的关键规则命中信息。
public enum RuleExecutionLogger {
    /// 中文注释：真值是 RuleExecutionStage；保留别名让既有调用点 `RuleExecutionLogger.Stage` 不变。
    public typealias Stage = RuleExecutionStage

    /// 中文注释：只输出短字段，不输出 HTML 或 Cookie 等敏感/巨大内容，避免控制台被噪音淹没。
    public static func log(stage: Stage, event: String, fields: [String: Any?]) {
        #if DEBUG
        RuleRuntimeDebugLog.shared.log(
            stage: stage,
            event: event,
            fields: fields.reduce(into: [String: String]()) { metadata, entry in
                metadata[entry.key] = entry.value.map(String.init(describing:)) ?? "nil"
            }
        )
        #endif
    }
}
