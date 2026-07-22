import Foundation

// 中文注释：同步模型只描述本地同步账本，不直接依赖 CloudKit。
enum SyncEntityType: String, Codable, Hashable {
    case source
    case favorite
    case favoriteItem
}

enum SyncQueueOperation: String, Codable, Hashable {
    case upsert
    case delete
}

struct SyncState: Hashable {
    var accountScope: CloudAccountScope
    var scope: String
    var zoneName: String
    var serverChangeTokenData: Data?
    var lastSyncedAt: Date?
    var updatedAt: Date

    init(
        accountScope: CloudAccountScope = .localDefault,
        scope: String,
        zoneName: String,
        serverChangeTokenData: Data?,
        lastSyncedAt: Date?,
        updatedAt: Date
    ) {
        self.accountScope = accountScope
        self.scope = scope
        self.zoneName = zoneName
        self.serverChangeTokenData = serverChangeTokenData
        self.lastSyncedAt = lastSyncedAt
        self.updatedAt = updatedAt
    }
}

struct SyncQueueItem: Identifiable, Hashable {
    var id: String
    var accountScope: CloudAccountScope
    var entityType: SyncEntityType
    var entityID: String
    var operation: SyncQueueOperation
    var updatedAt: Date
    var retryCount: Int
    var lastError: String?
    var createdAt: Date

    static func makeID(
        accountScope: CloudAccountScope,
        entityType: SyncEntityType,
        entityID: String
    ) -> String {
        return "\(accountScope.rawValue)|\(entityType.rawValue):\(entityID)"
    }
}
