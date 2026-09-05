import Foundation

/// 个人规则的本地保留期：收到后 7 天（用户 09-05 裁定）。
enum PersonalRuleRetentionPolicy {
    static let retentionInterval: TimeInterval = 7 * 24 * 60 * 60

    static func expiresAt(receivedAt: Date) -> Date {
        return receivedAt.addingTimeInterval(Self.retentionInterval)
    }

    static func remaining(receivedAt: Date, now: Date) -> TimeInterval {
        return max(0, Self.expiresAt(receivedAt: receivedAt).timeIntervalSince(now))
    }

    static func isExpired(receivedAt: Date, now: Date) -> Bool {
        return Self.remaining(receivedAt: receivedAt, now: now) <= 0
    }

    /// 剩余时间按「天 + 小时」向上取整到小时，最后一小时内显示「不足 1 小时」。
    static func remainingComponents(receivedAt: Date, now: Date) -> (days: Int, hours: Int) {
        let remaining: TimeInterval = Self.remaining(receivedAt: receivedAt, now: now)
        let totalHours: Int = Int((remaining / 3600).rounded(.up))
        return (days: totalHours / 24, hours: totalHours % 24)
    }
}
