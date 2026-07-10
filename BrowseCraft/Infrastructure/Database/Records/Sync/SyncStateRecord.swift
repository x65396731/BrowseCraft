import Foundation
import GRDB

// 中文注释：SyncStateRecord 是 sync_state 表的一行。
struct SyncStateRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName: String = "sync_state"

    var scope: String
    var zoneName: String
    var serverChangeTokenData: Data?
    var lastSyncedAt: Date?
    var updatedAt: Date

    init(state: SyncState) {
        self.scope = state.scope
        self.zoneName = state.zoneName
        self.serverChangeTokenData = state.serverChangeTokenData
        self.lastSyncedAt = state.lastSyncedAt
        self.updatedAt = state.updatedAt
    }

    func domainModel() -> SyncState {
        return SyncState(
            scope: self.scope,
            zoneName: self.zoneName,
            serverChangeTokenData: self.serverChangeTokenData,
            lastSyncedAt: self.lastSyncedAt,
            updatedAt: self.updatedAt
        )
    }
}
