import Foundation
import GRDB

/// 中文注释：删除账号后清本机数据（docs/design/Account-Deletion-Design.md 第五节第 6 步）。
/// 所有带 userID 的表都外键级联到 `users`（GRDB 默认开外键），删 `users` 一行即删净；
/// 按 iCloud 分区存放、不挂用户的同步游标、记录元数据与上传队列另按该用户关联过的分区删。
final class GRDBAccountDeletionLocalDataStore: AccountDeletionLocalDataStoring, Sendable {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func associatedCloudScopes(for userID: UUID) throws -> [CloudAccountScope] {
        return try self.database.queue.read { database in
            return try Self.associatedCloudScopes(for: userID.uuidString, in: database)
        }
    }

    func deleteLocalData(for userID: UUID) throws -> [String] {
        let databaseUserID: String = userID.uuidString
        return try self.database.queue.write { database in
            let scopes: [CloudAccountScope] = try Self.associatedCloudScopes(
                for: databaseUserID,
                in: database
            )
            let books: [LocalBookRecord] = try LocalBookRecord
                .filter(LocalBookRecord.Columns.userID == databaseUserID)
                .fetchAll(database)

            for scope: CloudAccountScope in scopes {
                _ = try SyncStateRecord
                    .filter(SyncStateRecord.Columns.accountScope == scope.rawValue)
                    .deleteAll(database)
                _ = try CloudRecordMetadataRecord
                    .filter(CloudRecordMetadataRecord.Columns.accountScope == scope.rawValue)
                    .deleteAll(database)
                _ = try SyncQueueRecord
                    .filter(SyncQueueRecord.Columns.accountScope == scope.rawValue)
                    .deleteAll(database)
            }
            _ = try AppUserRecord.deleteOne(database, key: databaseUserID)

            return books.flatMap { book in
                return [book.fileRelativePath] + (book.coverRelativePath.map { [$0] } ?? [])
            }
        }
    }

    private static func associatedCloudScopes(
        for databaseUserID: String,
        in database: Database
    ) throws -> [CloudAccountScope] {
        let rawScopes: [String] = try String.fetchAll(
            database,
            sql: """
            SELECT accountScope FROM \(CloudAppUserAssociationAttestationRecord.databaseTableName)
            WHERE userID = ?
            UNION
            SELECT accountScope FROM \(CloudAccountPartitionPreparationRecord.databaseTableName)
            WHERE userID = ?
            """,
            arguments: [databaseUserID, databaseUserID]
        )
        return rawScopes.sorted().map(CloudAccountScope.init(rawValue:))
    }
}
