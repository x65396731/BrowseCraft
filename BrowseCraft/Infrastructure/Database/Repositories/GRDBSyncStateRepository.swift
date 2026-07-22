import Foundation
import GRDB

// 中文注释：GRDBSyncStateRepository 保存同步进度书签，当前先为未来 CloudKit change token 预留。
final class GRDBSyncStateRepository: SyncStateRepository {
    private let database: AppDatabase
    private let accountScopeProvider: any ActiveAccountScopeProviding

    init(
        database: AppDatabase,
        accountScopeProvider: any ActiveAccountScopeProviding = ActiveAccountScopeStore()
    ) {
        self.database = database
        self.accountScopeProvider = accountScopeProvider
    }

    func fetchState(scope: String, zoneName: String) throws -> SyncState? {
        let accountScope: CloudAccountScope = self.accountScopeProvider.currentScope
        return try self.database.queue.read { database in
            return try SyncStateRecord
                .filter(
                    SyncStateRecord.Columns.accountScope == accountScope.rawValue &&
                    SyncStateRecord.Columns.scope == scope &&
                    SyncStateRecord.Columns.zoneName == zoneName
                )
                .fetchOne(database)?
                .domainModel()
        }
    }

    func saveState(_ state: SyncState) throws {
        var scopedState: SyncState = state
        scopedState.accountScope = self.accountScopeProvider.currentScope
        var record: SyncStateRecord = SyncStateRecord(state: scopedState)

        try self.database.queue.write { database in
            try record.save(database)
        }
    }
}
