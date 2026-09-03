import Foundation

// 中文注释：显式 runtime audit 的播放执行结果。它是 VideoSourceRuntime.auditPlaybackWithRouteFacts
// 的返回类型，因此随 runtime 走；驱动 audit 的开发者工具留在 App 侧。
#if DEBUG
public struct VideoAuditPlaybackExecution: Sendable {
    public let session: VideoPreparedPlaybackExecutionSession
    /// 中文注释：nil 表示 loader 执行阶段抛出（prepare 已成功）；此时逐槽位如实记 failed。
    public let result: VideoPreparedPlaybackExecutionResult?

    public init(
        session: VideoPreparedPlaybackExecutionSession,
        result: VideoPreparedPlaybackExecutionResult?
    ) {
        self.session = session
        self.result = result
    }
}
#endif
