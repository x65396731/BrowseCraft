import BrowseCraftLog
import Foundation
import SwiftUI

// 中文注释：统一日志的出口装配（Logging-Design.md 第 6 节）。`BrowseCraftApp.init` 第一件事调 `installBaseSinks`，
// 早于广告 SDK 与 Firebase；Crashlytics 出口要等 `CrashDiagnostics.configure` 之后由 AppDelegate 安装。

enum AppLogging {
    private static let osLogSink: OSLogSink = OSLogSink()
    private static let fileSink: LogFileSink = LogFileSink()
    private static let crashlyticsSink: CrashlyticsLogSink = CrashlyticsLogSink()

    /// 中文注释：OSLog 与本机文件两个出口，以及会话上下文。`session` 与 Crashlytics 的 `sessionId` 键同值，两边对得上。
    static func installBaseSinks() {
        AppLog.install(Self.osLogSink)
        AppLog.install(Self.fileSink)
        AppLog.setContext("session", DiagnosticIdentityStore.shared.identity.sessionId)
        AppLog.info(.diagnostics, "log-sinks-installed", [
            "build": .code(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String),
            "version": .code(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        ])
    }

    /// 中文注释：Crashlytics 出口，AppDelegate 在 `CrashDiagnostics.configure` 之后调用（BCA-OBS-017）。
    static func installCrashlyticsSink() {
        AppLog.install(Self.crashlyticsSink)
    }

    /// 中文注释：设置页「导出诊断日志」：先等后台队列写完，再把两个文件合成一份（BCA-OBS-016）。
    static func makeExportFile() throws -> URL {
        AppLog.flush()
        let url: URL = try Self.fileSink.makeExportFile()
        AppLog.notice(.diagnostics, "log-exported")
        return url
    }

    /// 中文注释：问题报告的日志片段（Problem-Report-Design.md 第六节）：本次会话最近 `window` 秒、指定类别的本机日志行。
    /// 只在用户点「发送」时读（`BCA-OBS-018`）；日志行本身已按 BCA-OBS-012 脱敏，这里不再处理。
    static func recentLogLines(
        window: TimeInterval,
        categories: Set<String>,
        maxLines: Int,
        maxBytes: Int
    ) -> [String] {
        AppLog.flush()
        return Self.fileSink.recentLines(
            sessionID: DiagnosticIdentityStore.shared.identity.sessionId,
            since: Date().addingTimeInterval(-window),
            categories: categories,
            maxLines: maxLines,
            maxBytes: maxBytes
        )
    }

    /// 中文注释：删除账号时清掉本机日志文件（BCA-OBS-016）。
    static func removeLocalLogFiles() {
        AppLog.flush()
        Self.fileSink.removeAllFiles()
    }

    /// 中文注释：页面公共钩子（BCA-OBS-014）：由 `AnalyticsScreenReporter` 在每次曝光时调用，
    /// 记一条 info，并把当前页面写进之后每条记录的上下文。
    static func logScreenShown(_ screen: DiagnosticScreen) {
        AppLog.setContext("screen", screen.rawValue)
        AppLog.info(.screen, "screen-shown", ["screen": .enumValue(screen)])
    }

    /// 中文注释：生命周期公共钩子（BCA-OBS-014）。
    static func logScenePhase(_ phase: ScenePhase) {
        let name: String
        switch phase {
        case .active:
            name = "active"
        case .inactive:
            name = "inactive"
        case .background:
            name = "background"
        @unknown default:
            name = "unknown"
        }
        AppLog.info(.lifecycle, "scene-phase-changed", ["phase": .code(name)])
    }
}
