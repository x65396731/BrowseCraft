import Foundation

/// 中文注释：CloudAccountSession 更新此快照，GRDB Repository 在每次事务开始前捕获一次 scope。
final class ActiveAccountScopeStore: ActiveAccountScopeProviding, @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private var scope: CloudAccountScope

    init(initialScope: CloudAccountScope = .localDefault) {
        self.scope = initialScope
    }

    var currentScope: CloudAccountScope {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.scope
    }

    func update(_ scope: CloudAccountScope) {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.scope = scope
    }
}
