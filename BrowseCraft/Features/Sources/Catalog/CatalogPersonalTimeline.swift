import BrowseCraftDomain
import Foundation

/// 「我的生成」时间线：成功规则与失败记录合并成一条，按终结时间倒序，按自然日分组。
///
/// 中文注释：`CatalogSourceGrouping` 把成功与失败分成两个数组，目录页原先各画一个 `ForEach`，
/// 用户看不出哪条是刚生成的。这里只重排、不增删——条目集合与分组结果完全一致。
/// 没有终结时间（`finishedAt` 缺失或解析不了）的条目放在最后一组「更早」，组内保持服务端顺序。
struct CatalogPersonalTimeline: Hashable {
    enum Entry: Identifiable, Hashable {
        case rule(CatalogSource)
        case failure(VideoGenerationOutcome)

        var id: String {
            switch self {
            case .rule(let catalogSource):
                return "rule-\(catalogSource.id)"
            case .failure(let outcome):
                return "failure-\(outcome.jobID.uuidString)"
            }
        }
    }

    enum Day: Hashable {
        case today
        case yesterday
        /// 当天零点。
        case date(Date)
        case unknown
    }

    struct DayGroup: Identifiable, Hashable {
        let day: Day
        let entries: [Entry]

        var id: Day {
            return self.day
        }
    }

    let groups: [DayGroup]

    var isEmpty: Bool {
        return self.groups.isEmpty
    }

    static func make(
        grouping: CatalogSourceGrouping,
        now: Date,
        calendar: Calendar
    ) -> CatalogPersonalTimeline {
        var dated: [(entry: Entry, date: Date?, order: Int)] = []
        for catalogSource: CatalogSource in grouping.personalSources {
            dated.append((
                entry: .rule(catalogSource),
                date: grouping.personalOutcomes[catalogSource.id]?.finishedDate,
                order: dated.count
            ))
        }
        for outcome: VideoGenerationOutcome in grouping.failedOutcomes {
            dated.append((entry: .failure(outcome), date: outcome.finishedDate, order: dated.count))
        }
        dated.sort { lhs, rhs in
            switch (lhs.date, rhs.date) {
            case (let left?, let right?) where left != right:
                return left > right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                return lhs.order < rhs.order
            }
        }

        var groups: [DayGroup] = []
        for item in dated {
            let day: Day = Self.day(for: item.date, now: now, calendar: calendar)
            if let last: DayGroup = groups.last, last.day == day {
                groups[groups.count - 1] = DayGroup(day: day, entries: last.entries + [item.entry])
            } else {
                groups.append(DayGroup(day: day, entries: [item.entry]))
            }
        }
        return CatalogPersonalTimeline(groups: groups)
    }

    private static func day(for date: Date?, now: Date, calendar: Calendar) -> Day {
        guard let date: Date = date else {
            return .unknown
        }
        if calendar.isDate(date, inSameDayAs: now) {
            return .today
        }
        if let yesterday: Date = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return .yesterday
        }
        return .date(calendar.startOfDay(for: date))
    }
}

/// 推荐：公共目录按类型分区，顺序固定为 视频 → 漫画 → 书籍；没有条目的类型不出现，区内保持服务端顺序。
struct CatalogKindSection: Identifiable, Hashable {
    static let order: [CatalogSourceKind] = [.video, .comic, .book]

    let kind: CatalogSourceKind
    let sources: [CatalogSource]

    var id: CatalogSourceKind {
        return self.kind
    }

    static func make(_ catalogSources: [CatalogSource]) -> [CatalogKindSection] {
        return Self.order.compactMap { kind in
            let sources: [CatalogSource] = catalogSources.filter { $0.kind == kind }
            return sources.isEmpty ? nil : CatalogKindSection(kind: kind, sources: sources)
        }
    }
}
