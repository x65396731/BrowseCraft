import Foundation

// 中文注释：RSSContentFormatters 放置 RSS 画面层复用的文本和日期格式化逻辑。

enum RSSContentTextFormatter {
    static func sanitized(_ text: String?) -> String? {
        guard let text: String = text else {
            return nil
        }

        let withoutTags: String = text.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        let decoded: String = withoutTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
        let collapsed: String = decoded
            .split(whereSeparator: { character in
                return character.isWhitespace
            })
            .joined(separator: " ")

        return collapsed.isEmpty ? nil : collapsed
    }
}

enum RSSContentDateFormatter {
    static func string(from date: Date) -> String {
        return Self.formatter.string(from: date)
    }

    private static let formatter: DateFormatter = {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
