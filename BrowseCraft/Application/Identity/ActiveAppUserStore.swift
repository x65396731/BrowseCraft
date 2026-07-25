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

/// 中文注释：每轮 Cloud Sync 固定业务 UUID；底层异步回调不得重新读取可能已切换的活动用户。
final class CloudSyncUserContext: @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private var synchronizedUserID: UUID?

    func begin(userID: UUID) {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.synchronizedUserID = userID
    }

    func end(userID: UUID) {
        self.lock.lock()
        defer { self.lock.unlock() }
        // 中文注释：保留最后一次固定 UUID，避免 CKSyncEngine 已取消但迟到的 delegate 回调落到新活动用户。
        guard self.synchronizedUserID == userID else {
            return
        }
    }

    var currentUserID: UUID? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.synchronizedUserID
    }
}
