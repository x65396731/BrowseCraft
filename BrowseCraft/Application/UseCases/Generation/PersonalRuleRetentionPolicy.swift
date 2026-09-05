import Foundation

/// 个人规则的本人可见期由服务器裁决（`expiresAt` = 终结 + 7 天）；这里只负责把剩余时间
/// 换算成「天 + 小时」用于显示。
enum PersonalRuleRetentionPolicy {
    static func remaining(expiresAt: Date, now: Date) -> TimeInterval {
        return max(0, expiresAt.timeIntervalSince(now))
    }

    /// 向上取整到小时；最后一小时内显示「即将到期」。
    static func remainingComponents(expiresAt: Date, now: Date) -> (days: Int, hours: Int) {
        let remaining: TimeInterval = Self.remaining(expiresAt: expiresAt, now: now)
        let totalHours: Int = Int((remaining / 3600).rounded(.up))
        return (days: totalHours / 24, hours: totalHours % 24)
    }
}
