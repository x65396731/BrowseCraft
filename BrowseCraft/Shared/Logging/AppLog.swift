import Foundation
import OSLog

enum AppLog {
    enum Category: String {
        case app
        case cache
        case credential
        case discovery
        case network
        case purchase
        case push
        case rule
        case startup
        case sync
        case video
    }

    static func debug(
        _ category: Category,
        event: String,
        metadata: [String: String] = [:]
    ) {
        #if DEBUG
        let message: String = self.message(event: event, metadata: metadata)
        self.logger(category).debug("\(message, privacy: .public)")
        #endif
    }

    static func notice(
        _ category: Category,
        event: String,
        metadata: [String: String] = [:]
    ) {
        let message: String = self.message(event: event, metadata: metadata)
        self.logger(category).notice("\(message, privacy: .public)")
    }

    static func error(
        _ category: Category,
        event: String,
        metadata: [String: String] = [:]
    ) {
        let message: String = self.message(event: event, metadata: metadata)
        self.logger(category).error("\(message, privacy: .public)")
    }

    /// 保留 scheme、host 与 path；认证信息、query 和 fragment 永不进入日志。
    static func safeURL(_ url: URL?) -> String {
        guard let url else {
            return "nil"
        }
        var components: URLComponents? = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )
        components?.user = nil
        components?.password = nil
        components?.query = nil
        components?.fragment = nil
        return components?.string ?? "invalid-url"
    }

    static func safeErrorCode(_ error: any Error) -> String {
        let nsError: NSError = error as NSError
        return "\(nsError.domain):\(nsError.code)"
    }

    /// 兼容尚未逐项结构化的旧调试点；先统一进入 OSLog，并清除常见秘密与 URL 查询参数。
    static func sanitizedDebugMessage(_ message: String) -> String {
        var result: String = message
        let patterns: [(String, String)] = [
            (#"(?i)(authorization|cookie|token|signature|password|secret)=\S+"#, "$1=<redacted>"),
            (#"(https?://[^\s?]+)\?\S+"#, "$1?<redacted>")
        ]
        for (pattern, replacement) in patterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }
        return result
    }

    private static func logger(_ category: Category) -> Logger {
        return Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "BrowseCraft",
            category: category.rawValue
        )
    }

    private static func message(
        event: String,
        metadata: [String: String]
    ) -> String {
        let fields: String = metadata.keys.sorted().map { key in
            return "\(key)=\(metadata[key] ?? "nil")"
        }.joined(separator: " ")
        return fields.isEmpty ? "event=\(event)" : "event=\(event) \(fields)"
    }
}

enum AppDebugLog {
    static func write(
        _ items: Any...,
        separator: String = " ",
        terminator _: String = "\n"
    ) {
        #if DEBUG
        let message: String = items.map { String(describing: $0) }
            .joined(separator: separator)
        AppLog.debug(
            .app,
            event: "debug",
            metadata: ["message": AppLog.sanitizedDebugMessage(message)]
        )
        #endif
    }
}
