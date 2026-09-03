import Foundation

/// 中文注释：规则执行链路的阶段标识。错误载荷与调试日志共用它，
/// 因此属于内核而不是 App 的日志实现。
public enum RuleExecutionStage: String, Hashable, Sendable {
    case list
    case search
    case detail
    case playback
    case reader
    case image
}
