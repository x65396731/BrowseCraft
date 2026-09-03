import BrowseCraftDomain
import Foundation

// 中文注释：RuleExecutionLogger.swift 统一规则执行链路的调试日志格式，便于回归时快速定位断点。

/// 中文注释：Debug 环境下记录列表、详情、阅读页和图片请求的关键规则命中信息。
enum RuleExecutionLogger {
    /// 中文注释：真值在 BrowseCraftDomain.RuleExecutionStage；这里保留别名，既有调用点不变。
    typealias Stage = RuleExecutionStage

    /// 中文注释：只输出短字段，不输出 HTML 或 Cookie 等敏感/巨大内容，避免控制台被噪音淹没。
    static func log(stage: Stage, event: String, fields: [String: Any?]) {
        #if DEBUG
        var metadata: [String: String] = ["stage": stage.rawValue]
        fields.forEach { key, value in
            metadata[key] = value.map(String.init(describing:)) ?? "nil"
        }
        AppLog.debug(.rule, event: event, metadata: metadata)
        #endif
    }
}
