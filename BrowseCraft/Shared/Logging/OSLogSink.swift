import BrowseCraftLog
import Foundation
import OSLog

// 中文注释：OSLog 出口，全仓唯一一处 `import OSLog` 与 `Logger(`（BCA-OBS-010）。
// 字段在 `LogValue` 构造时已按类型脱敏，这里统一标 `privacy: .public`，控制台与 sysdiagnose 里才看得到内容。

final class OSLogSink: LogSink {
    let minimumLevel: LogLevel = .debug
    private let loggers: [LogCategory: Logger]

    init(subsystem: String = Bundle.main.bundleIdentifier ?? "BrowseCraft") {
        self.loggers = Dictionary(uniqueKeysWithValues: LogCategory.allCases.map { category in
            (category, Logger(subsystem: subsystem, category: category.rawValue))
        })
    }

    func write(_ record: LogRecord) {
        guard let logger: Logger = self.loggers[record.category] else {
            return
        }
        let message: String = record.message
        switch record.level {
        case .debug:
            logger.debug("\(message, privacy: .public)")
        case .info:
            logger.info("\(message, privacy: .public)")
        case .notice:
            logger.notice("\(message, privacy: .public)")
        case .error:
            logger.error("\(message, privacy: .public)")
        case .fault:
            logger.fault("\(message, privacy: .public)")
        }
    }
}
