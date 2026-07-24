import Foundation

/// 中文注释：活动业务用户与 CloudAccountScope 独立，后续可在确认云端身份后原子切换。
final class ActiveAppUserStore: ActiveAppUserProviding, @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private var userID: UUID

    init(initialUserID: UUID) {
        self.userID = initialUserID
    }

    var currentUserID: UUID {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.userID
    }

    func update(_ userID: UUID) {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.userID = userID
    }
}
