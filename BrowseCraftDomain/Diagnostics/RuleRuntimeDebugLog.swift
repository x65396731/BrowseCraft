import Foundation

/// 中文注释：规则执行链路的一条诊断记录。stage 为 nil 表示不属于某个执行阶段的自由文本调试输出。
public struct RuleRuntimeLogRecord: Sendable {
    public let stage: RuleExecutionStage?
    public let event: String
    public let fields: [String: String]

    public init(
        stage: RuleExecutionStage? = nil,
        event: String,
        fields: [String: String] = [:]
    ) {
        self.stage = stage
        self.event = event
        self.fields = fields
    }
}

/// 中文注释：规则执行链路的调试日志出口。内核与 runtime 不依赖 App 的 AppLog/OSLog 分类，
/// 只把记录交给 App 在启动时安装的 sink；未安装时是 no-op。
/// 仅 DEBUG 生效——Release 下消息与字段都不会被求值。
/// sink 由 NSLock 保护，因此 @unchecked Sendable。
public final class RuleRuntimeDebugLog: @unchecked Sendable {
    public typealias Sink = @Sendable (RuleRuntimeLogRecord) -> Void

    public static let shared: RuleRuntimeDebugLog = RuleRuntimeDebugLog()

    private let lock: NSLock = NSLock()
    private var sink: Sink?

    private init() {}

    /// 中文注释：由组合根在启动时安装；重复安装以最后一次为准。
    public func install(_ sink: @escaping Sink) {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.sink = sink
    }

    public func log(
        stage: RuleExecutionStage,
        event: String,
        fields: @autoclosure () -> [String: String]
    ) {
        #if DEBUG
        guard let sink: Sink = self.currentSink() else {
            return
        }
        sink(RuleRuntimeLogRecord(stage: stage, event: event, fields: fields()))
        #endif
    }

    /// 中文注释：自由文本调试输出，等价于 App 侧的 AppDebugLog.write。
    public func write(_ message: @autoclosure () -> String) {
        #if DEBUG
        guard let sink: Sink = self.currentSink() else {
            return
        }
        sink(RuleRuntimeLogRecord(event: "debug", fields: ["message": message()]))
        #endif
    }

    private func currentSink() -> Sink? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.sink
    }
}
