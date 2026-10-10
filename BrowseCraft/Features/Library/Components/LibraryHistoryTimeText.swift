import Foundation

/// 同一条历史在库页「上次看到 / 读到」瓷砖、漫画详情与书详情继续卡片上的「时刻」写法，只此一处
/// （2026-10-10 复审第七批统一；此前两个详情页各自一份 `DateFormatter.doesRelativeDateFormatting`，与库页写法不同）：
/// 今天、昨天写「今天 21:30」「昨天 09:12」，更早的只写日期（跨年带年份）——组头文字与目录「我的生成」、收藏页同一套 `CatalogDayTitle`。
enum LibraryHistoryTimeText {
    static func text(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let day: CatalogPersonalTimeline.Day = CatalogPersonalTimeline.day(for: date, now: now, calendar: calendar)
        let dayText: String = CatalogDayTitle.text(for: day, now: now, calendar: calendar)
        switch day {
        case .today, .yesterday:
            return dayText + " " + date.formatted(date: .omitted, time: .shortened)
        case .date, .unknown:
            return dayText
        }
    }
}
