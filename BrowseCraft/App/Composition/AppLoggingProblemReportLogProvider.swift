import Foundation

/// 中文注释：问题报告读日志片段的端口接到 `AppLogging`（Problem-Report-Design.md 第六、七节）。
/// 端口在 Application、实现在 Shared，Shared 不得引用 Application，所以由组合根接线。
struct AppLoggingProblemReportLogProvider: ProblemReportLogProviding {
    func recentLogLines(window: TimeInterval, categories: Set<String>, maxLines: Int, maxBytes: Int) -> [String] {
        return AppLogging.recentLogLines(window: window, categories: categories, maxLines: maxLines, maxBytes: maxBytes)
    }
}
