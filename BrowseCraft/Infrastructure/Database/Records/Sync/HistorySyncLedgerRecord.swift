import Foundation
@preconcurrency import GRDB

// 中文注释：HistorySyncLedgerRecord 是 history_sync_ledger 表的一行，主键 (userID, kind, sourceID, workKey)。
// 每部作品一行：`changedAt` 是上次与云端对齐时这部作品的改动时间，`deletedAt` 非空表示这部作品的历史已删除。

struct HistorySyncLedgerRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName: String = "history_sync_ledger"

    var userID: String
    var kind: String
    var sourceID: String
    var workKey: String
    var changedAt: Date
    var deletedAt: Date?

    enum Columns {
        static let userID: Column = Column("userID")
        static let kind: Column = Column("kind")
        static let sourceID: Column = Column("sourceID")
        static let workKey: Column = Column("workKey")
        static let changedAt: Column = Column("changedAt")
        static let deletedAt: Column = Column("deletedAt")
    }

    var identity: HistoryEntryIdentity {
        return HistoryEntryIdentity(kind: self.kind, sourceID: self.sourceID, workKey: self.workKey)
    }
}
