import Foundation

// 中文注释：RSSContentFormatters 放置 RSS 画面层复用的文本和日期格式化逻辑。

enum RSSContentTextFormatter {
    static func sanitized(_ text: String?) -> String? {
        if let payload: RSSContentPayload = RSSContentPayload.decode(from: text) {
            return payload.summaryText
        }

        return Self.sanitizedHTML(text)
    }

    static func sanitizedHTML(_ text: String?) -> String? {
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

    static func dayMonthString(from date: Date) -> String {
        let day: Int = Calendar.current.component(.day, from: date)
        return "\(day)\(Self.ordinalSuffix(for: day)) \(Self.monthFormatter.string(from: date))"
    }

    static func timeString(from date: Date) -> String {
        return Self.timeFormatter.string(from: date)
    }

    static func monthDayString(from date: Date) -> String {
        return Self.monthDayFormatter.string(from: date)
    }

    private static let formatter: DateFormatter = {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "MMM"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "h : mm a"
        return formatter
    }()

    private static let monthDayFormatter: DateFormatter = {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private static func ordinalSuffix(for day: Int) -> String {
        let teenRange: ClosedRange<Int> = 11...13
        if teenRange.contains(day % 100) {
            return "th"
        }

        switch day % 10 {
        case 1:
            return "st"
        case 2:
            return "nd"
        case 3:
            return "rd"
        default:
            return "th"
        }
    }
}
