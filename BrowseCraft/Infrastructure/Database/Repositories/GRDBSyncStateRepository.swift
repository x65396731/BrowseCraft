import Foundation
import GRDB

// 中文注释：GRDBSyncStateRepository 保存同步进度书签，当前先为未来 CloudKit change token 预留。
final class GRDBSyncStateRepository: SyncStateRepository {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func fetchState(scope: String, zoneName: String) throws -> SyncState? {
        return try self.database.queue.read { database in
            return try SyncStateRecord
                .filter(
                    SyncStateRecord.Columns.scope == scope &&
                    SyncStateRecord.Columns.zoneName == zoneName
                )
                .fetchOne(database)?
                .domainModel()
        }
    }

    func saveState(_ state: SyncState) throws {
        var record: SyncStateRecord = SyncStateRecord(state: state)

        try self.database.queue.write { database in
            try record.save(database)
        }
    }
}
