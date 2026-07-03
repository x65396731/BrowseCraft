import Foundation

// 中文注释：RuleExecutionLogger.swift 统一规则执行链路的调试日志格式，便于回归时快速定位断点。

/// 中文注释：Debug 环境下记录列表、详情、阅读页和图片请求的关键规则命中信息。
enum RuleExecutionLogger {
    enum Stage: String {
        case list
        case search
        case detail
        case reader
        case image
    }

    /// 中文注释：只输出短字段，不输出 HTML 或 Cookie 等敏感/巨大内容，避免控制台被噪音淹没。
    static func log(stage: Stage, event: String, fields: [String: Any?]) {
        #if DEBUG
        let fieldText: String = fields
            .compactMap { key, value in
                guard let value: Any = value else {
                    return "\(key)=nil"
                }

                return "\(key)=\(String(describing: value))"
            }
            .joined(separator: " ")

        print("[BrowseCraftRuleTrace] stage=\(stage.rawValue) event=\(event) \(fieldText)")
        #endif
    }
}
