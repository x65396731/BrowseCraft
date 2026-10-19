import BrowseCraftDomain
import Foundation
import GRDB

// 中文注释：GRDBSourceRepository 通过 SQLite 保存、读取和删除 Source。

/// 中文注释：Source 删除只动来源自己（`BCA-DB-004`、`BCA-DB-005`）：同一写事务里软删来源、清空指向它的库当前选择；
/// 历史与收藏保留，被删来源的条目靠记录里的来源快照显示与打开。来源与库状态作为留底交回，撤销时由 `restoreDeletedSource` 写回。
final class GRDBSourceRepository: SourceRepository {
    private let database: AppDatabase
    private let activeAppUser: (any ActiveAppUserProviding)?
    private let accountScopeProvider: any ActiveAccountScopeProviding
    private let changeNotifier: (any CloudSyncChangeNotifying)?

    init(
        database: AppDatabase,
        activeAppUser: (any ActiveAppUserProviding)? = nil,
        accountScopeProvider: any ActiveAccountScopeProviding = ActiveAccountScopeStore(),
        changeNotifier: (any CloudSyncChangeNotifying)? = nil
    ) {
        self.database = database
        self.activeAppUser = activeAppUser
        self.accountScopeProvider = accountScopeProvider
        self.changeNotifier = changeNotifier
    }

    func fetchSources() throws -> [Source] {
        let userID: String = self.currentUserID
        return try self.database.queue.read { database in
            return try Self.fetchDomainSources(userID: userID, in: database)
        }
    }

    private static func fetchDomainSources(userID: String, in database: Database) throws -> [Source] {
        let records: [SourceRecord] = try SourceRecord
            .filter(SourceRecord.Columns.userID == userID)
            .filter(SourceRecord.Columns.deletedAt == nil)
            .order(SourceRecord.Columns.updatedAt.desc)
            .fetchAll(database)

        return try records.map { record in
            return try record.domainModel()
        }
    }

    /// 中文注释：槽位归置用的候选查询——非内置、未删除，按启用、更新时间、id 排序；读判断与写归置共用同一份 SQL。
    private static func fetchSlotCandidateRecords(userID: String, in database: Database) throws -> [SourceRecord] {
        return try SourceRecord.fetchAll(
            database,
            sql: """
            SELECT *
            FROM \(SourceRecord.databaseTableName)
            WHERE userID = ?
              AND deletedAt IS NULL
              AND id NOT LIKE 'built-in.%'
            ORDER BY enabled DESC, updatedAt DESC, id ASC
            """,
            arguments: [userID]
        )
    }

    private static func siteSlotLimit(userID: String, in database: Database) throws -> Int {
        let entitlementUser: AppUserRecord? = try AppUserRecord.fetchOne(database, key: userID)
        return SourceSlotPolicy.effectiveLimit(
            storedLimit: entitlementUser?.siteSlotLimit ?? SourceSlotPolicy.includedSiteSlotCount
        )
    }

    private enum ReconcileReadOutcome {
        /// 已按槽位规则就位，且用户行存在：直接返回同一次读事务里解出的来源。
        case settled([Source])
        /// 有来源的启用状态需要翻转，或用户行尚不存在：进入写事务。
        case needsWrite
    }

    func saveSource(_ source: Source) throws {
        try self.saveCatalogSources([source], fingerprintsBySourceID: [:])
    }

    /// 中文注释：一个写事务里逐条保存；指纹表里有的来源把 `catalogRuleFingerprint` 一起写上（复审 B-4）。
    func saveCatalogSources(_ sources: [Source], fingerprintsBySourceID: [String: String]) throws {
        guard sources.isEmpty == false else {
            return
        }
        let userID: String = self.currentUserID
        let accountScope: CloudAccountScope = self.accountScopeProvider.currentScope
        try self.database.queue.write { database in
            try AppUserRecord.insertUser(id: userID, in: database)
            for source: Source in sources {
                try Self.save(
                    source,
                    catalogRuleFingerprint: fingerprintsBySourceID[source.id],
                    userID: userID,
                    accountScope: accountScope,
                    in: database
                )
            }
        }
        if sources.contains(where: { $0.isBuiltIn == false }) {
            self.changeNotifier?.notifyLocalChange()
        }
    }

    func catalogRuleFingerprints() throws -> [String: String] {
        let userID: String = self.currentUserID
        return try self.database.queue.read { database in
            let rows: [Row] = try Row.fetchAll(
                database,
                sql: """
                SELECT id, catalogRuleFingerprint
                FROM \(SourceRecord.databaseTableName)
                WHERE userID = ? AND deletedAt IS NULL AND catalogRuleFingerprint IS NOT NULL
                """,
                arguments: [userID]
            )
            var fingerprints: [String: String] = [:]
            for row: Row in rows {
                fingerprints[row["id"]] = row["catalogRuleFingerprint"]
            }
            return fingerprints
        }
    }

    func stampCatalogRuleFingerprints(_ fingerprintsBySourceID: [String: String]) throws {
        guard fingerprintsBySourceID.isEmpty == false else {
            return
        }
        let userID: String = self.currentUserID
        try self.database.queue.write { database in
            for (sourceID, fingerprint) in fingerprintsBySourceID {
                try database.execute(
                    sql: """
                    UPDATE \(SourceRecord.databaseTableName)
                    SET catalogRuleFingerprint = ?
                    WHERE userID = ? AND id = ?
                    """,
                    arguments: [fingerprint, userID, sourceID]
                )
            }
        }
    }

    func stampCatalogRevisions(_ revisionsBySourceID: [String: String]) throws {
        guard revisionsBySourceID.isEmpty == false else {
            return
        }
        let userID: String = self.currentUserID
        try self.database.queue.write { database in
            for (sourceID, revision) in revisionsBySourceID {
                try database.execute(
                    sql: """
                    UPDATE \(SourceRecord.databaseTableName)
                    SET catalogRevision = ?
                    WHERE userID = ? AND id = ?
                    """,
                    arguments: [revision, userID, sourceID]
                )
            }
        }
    }

    func catalogRevision(sourceID: String) throws -> String? {
        let userID: String = self.currentUserID
        return try self.database.queue.read { database in
            return try String.fetchOne(
                database,
                sql: """
                SELECT catalogRevision
                FROM \(SourceRecord.databaseTableName)
                WHERE userID = ? AND id = ?
                """,
                arguments: [userID, sourceID]
            )
        }
    }

    private static func save(
        _ source: Source,
        catalogRuleFingerprint: String?,
        userID: String,
        accountScope: CloudAccountScope,
        in database: Database
    ) throws {
        let existingRecord: SourceRecord? = try SourceRecord.fetchOne(
            database,
            key: ["userID": userID, "id": source.id]
        )
        let existingSourceConsumesSlot: Bool = existingRecord.map { record in
            return record.deletedAt == nil
                && record.id.hasPrefix("built-in.") == false
                && record.enabled
        } ?? false
        if SourceSlotPolicy.consumesNewSlot(
            source: source,
            existingSourceConsumesSlot: existingSourceConsumesSlot
        ) {
            let entitlementUser: AppUserRecord? = try AppUserRecord.fetchOne(
                database,
                key: userID
            )
            let siteSlotLimit: Int = SourceSlotPolicy.effectiveLimit(
                storedLimit: entitlementUser?.siteSlotLimit ?? SourceSlotPolicy.includedSiteSlotCount
            )
            let occupiedSiteSlotCount: Int = try Int.fetchOne(
                database,
                sql: """
                SELECT COUNT(*)
                FROM \(SourceRecord.databaseTableName)
                WHERE userID = ?
                  AND deletedAt IS NULL
                  AND id NOT LIKE 'built-in.%'
                  AND enabled = 1
                """,
                arguments: [userID]
            ) ?? 0

            guard occupiedSiteSlotCount < siteSlotLimit else {
                throw SourceRepositoryError.siteSlotLimitReached(limit: siteSlotLimit)
            }
        }

        var record: SourceRecord = try SourceRecord(source: source)
        record.userID = userID
        record.catalogRuleFingerprint = catalogRuleFingerprint
        // 中文注释：规则版本只由目录应用路径改写（`stampCatalogRevisions`），其它整行保存保留旧值（`BCA-OBS-022`）。
        record.catalogRevision = existingRecord?.catalogRevision
        try record.save(database)

        if source.isBuiltIn == false {
            try SyncQueueRecord.enqueue(
                accountScope: accountScope,
                entityType: .source,
                entityID: source.id,
                operation: .upsert,
                updatedAt: source.updatedAt,
                in: database
            )
        }
    }

    func reconcileSourceSlotAssignments() throws -> [Source] {
        let userID: String = self.currentUserID
        let accountScope: CloudAccountScope = self.accountScopeProvider.currentScope
        var changedSourceCount: Int = 0

        // 中文注释：每次进列表都会调用。先在读事务里判断是否真的需要归置；多数情况下没有任何来源
        // 需要翻转启用状态，此时直接返回这次读出的来源，不开写事务（写事务会与 CloudSync 写者争 WAL 写锁），
        // 也不再第二次读出并解码全部来源。用户行不存在时仍走写路径，保持「归置后用户行必定存在」的不变量。
        let readOutcome: ReconcileReadOutcome = try self.database.queue.read { database in
            guard try AppUserRecord.exists(database, key: userID) else {
                return .needsWrite
            }
            let siteSlotLimit: Int = try Self.siteSlotLimit(userID: userID, in: database)
            let records: [SourceRecord] = try Self.fetchSlotCandidateRecords(userID: userID, in: database)
            let activeSourceIDs: Set<String> = Set(records.prefix(siteSlotLimit).map(\.id))
            let needsChange: Bool = records.contains { record in
                return record.enabled != activeSourceIDs.contains(record.id)
            }
            guard needsChange == false else {
                return .needsWrite
            }
            return .settled(try Self.fetchDomainSources(userID: userID, in: database))
        }
        if case .settled(let sources) = readOutcome {
            return sources
        }

        try self.database.queue.write { database in
            try AppUserRecord.insertUser(id: userID, in: database)
            let siteSlotLimit: Int = try Self.siteSlotLimit(userID: userID, in: database)
            let records: [SourceRecord] = try Self.fetchSlotCandidateRecords(userID: userID, in: database)
            let activeSourceIDs: Set<String> = Set(
                records.prefix(siteSlotLimit).map(\.id)
            )
            let now: Date = Date()

            for var record: SourceRecord in records {
                let shouldBeEnabled: Bool = activeSourceIDs.contains(record.id)
                guard record.enabled != shouldBeEnabled else {
                    continue
                }

                record.enabled = shouldBeEnabled
                record.updatedAt = now
                try record.save(database)
                if shouldBeEnabled == false {
                    try Self.clearSourceSelection(
                        userID: userID,
                        sourceID: record.id,
                        in: database
                    )
                }
                try SyncQueueRecord.enqueue(
                    accountScope: accountScope,
                    entityType: .source,
                    entityID: record.id,
                    operation: .upsert,
                    updatedAt: record.updatedAt,
                    in: database
                )
                changedSourceCount += 1
            }
        }

        if changedSourceCount > 0 {
            self.changeNotifier?.notifyLocalChange()
        }
        return try self.fetchSources()
    }

    func activateSource(
        id: String,
        replacingSourceID: String?
    ) throws -> [Source] {
        let userID: String = self.currentUserID
        let accountScope: CloudAccountScope = self.accountScopeProvider.currentScope
        var changedSourceCount: Int = 0

        try self.database.queue.write { database in
            try AppUserRecord.insertUser(id: userID, in: database)
            guard var target: SourceRecord = try SourceRecord.fetchOne(
                database,
                key: ["userID": userID, "id": id]
            ),
                  target.deletedAt == nil,
                  target.id.hasPrefix("built-in.") == false else {
                throw SourceRepositoryError.invalidSourceSlotReplacement
            }
            guard target.enabled == false else {
                return
            }

            let entitlementUser: AppUserRecord? = try AppUserRecord.fetchOne(
                database,
                key: userID
            )
            let siteSlotLimit: Int = SourceSlotPolicy.effectiveLimit(
                storedLimit: entitlementUser?.siteSlotLimit ??
                    SourceSlotPolicy.includedSiteSlotCount
            )
            let occupiedSiteSlotCount: Int = try Int.fetchOne(
                database,
                sql: """
                SELECT COUNT(*)
                FROM \(SourceRecord.databaseTableName)
                WHERE userID = ?
                  AND deletedAt IS NULL
                  AND id NOT LIKE 'built-in.%'
                  AND enabled = 1
                """,
                arguments: [userID]
            ) ?? 0
            let now: Date = Date()
            var changedRecords: [SourceRecord] = []

            if occupiedSiteSlotCount >= siteSlotLimit {
                guard let replacingSourceID,
                      replacingSourceID != id,
                      var replacement: SourceRecord = try SourceRecord.fetchOne(
                        database,
                        key: ["userID": userID, "id": replacingSourceID]
                      ),
                      replacement.deletedAt == nil,
                      replacement.id.hasPrefix("built-in.") == false,
                      replacement.enabled else {
                    throw SourceRepositoryError.invalidSourceSlotReplacement
                }
                replacement.enabled = false
                replacement.updatedAt = now
                try Self.clearSourceSelection(
                    userID: userID,
                    sourceID: replacement.id,
                    in: database
                )
                changedRecords.append(replacement)
            }

            target.enabled = true
            target.updatedAt = now
            changedRecords.append(target)

            for var record: SourceRecord in changedRecords {
                try record.save(database)
                try SyncQueueRecord.enqueue(
                    accountScope: accountScope,
                    entityType: .source,
                    entityID: record.id,
                    operation: .upsert,
                    updatedAt: record.updatedAt,
                    in: database
                )
                changedSourceCount += 1
            }
        }

        if changedSourceCount > 0 {
            self.changeNotifier?.notifyLocalChange()
        }
        return try self.fetchSources()
    }

    /// 中文注释：用户删除来源：软删来源、清空库的当前选择，历史与收藏不动（`BCA-DB-005`）。这里**不**发本地变更通知：
    /// 删除后有一段撤销窗口，通知由调用方在窗口结束时经 `notifyLocalChanges()` 补发，撤销了就不发——删除在窗口里一般不会被上传。
    @discardableResult
    func deleteSource(id: String) throws -> SourceDeletionReceipt? {
        let userID: String = self.currentUserID
        let accountScope: CloudAccountScope = self.accountScopeProvider.currentScope
        let isBuiltIn: Bool = id.hasPrefix("built-in.")
        return try self.database.queue.write { database -> SourceDeletionReceipt? in
            let now: Date = Date()
            let existingRecord: SourceRecord? = try SourceRecord.fetchOne(
                database,
                key: ["userID": userID, "id": id]
            )
            // 中文注释：留底只给在册且能解出来的来源；解不出配置的来源照样删，只是不能撤销。
            let liveSource: Source? = existingRecord.flatMap { (record: SourceRecord) -> Source? in
                guard record.deletedAt == nil else {
                    return nil
                }
                return try? record.domainModel()
            }
            let librarySelection: UserLibraryState? = try UserLibraryStateRecord
                .filter(UserLibraryStateRecord.Columns.userID == userID)
                .fetchOne(database)
                .flatMap { (record: UserLibraryStateRecord) -> UserLibraryState? in
                    return record.selectedSourceID == id ? record.domainModel() : nil
                }

            try Self.clearSourceSelection(
                userID: userID,
                sourceID: id,
                in: database
            )

            if var record: SourceRecord = existingRecord {
                record.updatedAt = now
                record.deletedAt = now
                try record.save(database)
            }

            if isBuiltIn == false {
                try SyncQueueRecord.enqueue(
                    accountScope: accountScope,
                    entityType: .source,
                    entityID: id,
                    operation: .delete,
                    updatedAt: now,
                    in: database
                )
            }

            guard let source: Source = liveSource else {
                return nil
            }
            return SourceDeletionReceipt(
                source: source,
                librarySelection: librarySelection,
                enqueuedSyncChanges: isBuiltIn == false
            )
        }
    }

    /// 中文注释：撤销删除：来源恢复为在册（更新时间取当前时间，启用状态照旧），非内置来源以当前时间重新入队为更新——
    /// `SyncQueueRecord.enqueue` 让较新的更新覆盖尚未上传的删除。删除前它是当前来源的，库状态也一并写回。
    /// 历史与收藏删除时没动，这里也不碰。
    func restoreDeletedSource(_ receipt: SourceDeletionReceipt) throws {
        let userID: String = self.currentUserID
        let accountScope: CloudAccountScope = self.accountScopeProvider.currentScope
        let isBuiltIn: Bool = receipt.source.isBuiltIn
        try self.database.queue.write { database in
            let now: Date = Date()
            try AppUserRecord.insertUser(id: userID, in: database)

            var record: SourceRecord = try SourceRecord(source: receipt.source)
            record.userID = userID
            record.deletedAt = nil
            record.updatedAt = now
            try record.save(database)
            if isBuiltIn == false {
                try SyncQueueRecord.enqueue(
                    accountScope: accountScope,
                    entityType: .source,
                    entityID: receipt.source.id,
                    operation: .upsert,
                    updatedAt: now,
                    in: database
                )
            }

            if var librarySelection: UserLibraryState = receipt.librarySelection {
                librarySelection.userID = userID
                librarySelection.updatedAt = now
                var stateRecord: UserLibraryStateRecord = try UserLibraryStateRecord(state: librarySelection)
                try stateRecord.save(database)
            }
        }
        if isBuiltIn == false {
            self.changeNotifier?.notifyLocalChange()
        }
    }

    func notifyLocalChanges() {
        self.changeNotifier?.notifyLocalChange()
    }

    /// 中文注释：删除来源（本机用户删除或 iCloud 应用远端删除）时，库的当前选择正好是它就清空（`BCA-DB-004`）。
    /// 历史与收藏保留（`BCA-DB-005`），这里不碰。
    static func clearSourceSelection(
        userID: String,
        sourceID: String,
        in database: Database
    ) throws {
        try database.execute(
            sql: """
            UPDATE \(UserLibraryStateRecord.databaseTableName)
            SET selectedSourceID = NULL,
                listContextJSON = NULL,
                lastRefreshAt = NULL,
                updatedAt = ?
            WHERE userID = ? AND selectedSourceID = ?
            """,
            arguments: [
                Date(),
                userID,
                sourceID
            ]
        )
    }

    /// 中文注释：nil 仅保留给既存隔离测试；App Composition Root 必须注入稳定业务用户。
    private var currentUserID: String {
        return self.activeAppUser?.currentUserID.uuidString ?? AppUser.localDefaultID
    }
}

