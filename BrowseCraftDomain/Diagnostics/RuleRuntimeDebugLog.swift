import Foundation

/// 中文注释：规则执行链路的调试日志出口。内核与 runtime 不依赖 App 的 AppLog/OSLog 分类，
/// 只把消息交给 App 在启动时安装的 sink；未安装时是 no-op。
/// 仅 DEBUG 生效——Release 下 `write` 的消息闭包不会被求值。
/// sink 由 NSLock 保护，因此 @unchecked Sendable。
public final class RuleRuntimeDebugLog: @unchecked Sendable {
    public typealias Sink = @Sendable (String) -> Void

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

    public func write(_ message: @autoclosure () -> String) {
        #if DEBUG
        self.lock.lock()
        let sink: Sink? = self.sink
        self.lock.unlock()
        sink?(message())
        #endif
    }
}
