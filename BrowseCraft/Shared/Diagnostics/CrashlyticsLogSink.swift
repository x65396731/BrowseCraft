import BrowseCraftLog
import Foundation

// 中文注释：统一日志的 Crashlytics 出口（Logging-Design.md `BCA-OBS-017`）。notice 及以上只写类别与事件名、不带字段，
// 崩溃报告里因此能看到崩溃前的关键过程；字段仍只留在本机日志里。

final class CrashlyticsLogSink: LogSink {
    let minimumLevel: LogLevel = .notice

    func write(_ record: LogRecord) {
        CrashDiagnostics.shared.logLine(category: record.category.rawValue, event: record.event)
    }
}
