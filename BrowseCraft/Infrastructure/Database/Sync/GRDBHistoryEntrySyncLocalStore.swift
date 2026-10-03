import Foundation
import GRDB

// 中文注释：续看位置同步的本机存储（`docs/design/History-Resume-Sync-Design.md` 第四节）。
// 三张历史表各管各的写入，这里不要求它们登记同步：每轮同步先 `registerLocalChanges`，
// 拿历史表与 history_sync_ledger 对比，找出新增、改动、删除与恢复的作品，再登记进 sync_queue。
final class GRDBHistoryEntrySyncLocalStore: HistoryEntrySyncLocalStore {
    private let database: AppDatabase
    private let activeAppUser: (any ActiveAppUserProviding)?
    private let userContext: CloudSyncUserContext?
    private let now: @Sendable () -> Date

    init(
        database: AppDatabase,
        activeAppUser: (any ActiveAppUserProviding)? = nil,
        userContext: CloudSyncUserContext? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.database = database
        self.activeAppUser = activeAppUser
        self.userContext = userContext
        self.now = now
    }

    // MARK: - 登记本机改动

    func registerLocalChanges(accountScope: CloudAccountScope) throws -> Int {
        let userID: String = self.currentUserID
        let now: Date = self.now()
        return try self.database.queue.write { database in
            try AppUserRecord.insertUser(id: userID, in: database)
            let liveTimes: [HistoryEntryIdentity: Date] = try Self.liveWorkTimes(userID: userID, in: database)
            let availableSourceIDs: Set<String> = try Self.availableSourceIDs(
                among: Set(liveTimes.keys.map(\.sourceID)),
                userID: userID,
                in: database
            )
            let ledgerRecords: [HistorySyncLedgerRecord] = try HistorySyncLedgerRecord
                .filter(HistorySyncLedgerRecord.Columns.userID == userID)
                .fetchAll(database)
            let ledger: [HistoryEntryIdentity: HistorySyncLedgerRecord] = Dictionary(
                ledgerRecords.map { ($0.identity, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            var registeredCount: Int = 0

            for (identity, rowTime): (HistoryEntryIdentity, Date) in liveTimes {
                // 中文注释：来源不在本机（已删除、或属于另一个数据空间）的历史不上传，对端也用不了。
                guard availableSourceIDs.contains(identity.sourceID) else {
                    continue
                }
                let changedAt: Date
                if let entry: HistorySyncLedgerRecord = ledger[identity] {
                    if entry.deletedAt != nil {
                        // 账本记着已删除、历史表里却又有了：撤销删除或重新看了这部作品。用现在的时间盖过删除标记。
                        changedAt = max(now, rowTime)
                    } else if rowTime > entry.changedAt {
                        changedAt = rowTime
                    } else {
                        continue
                    }
                } else {
                    changedAt = rowTime
                }
                try Self.saveLedger(identity, userID: userID, changedAt: changedAt, deletedAt: nil, in: database)
                try Self.enqueue(identity, operation: .upsert, updatedAt: changedAt, accountScope: accountScope, in: database)
                registeredCount += 1
            }

            for entry: HistorySyncLedgerRecord in ledgerRecords
            where entry.deletedAt == nil && liveTimes[entry.identity] == nil {
                // 账本里还活着、历史表里没有了：这部作品的历史被删了（单独删除，或随来源删除一起删）。
                try Self.saveLedger(entry.identity, userID: userID, changedAt: now, deletedAt: now, in: database)
                try Self.enqueue(entry.identity, operation: .delete, updatedAt: now, accountScope: accountScope, in: database)
                registeredCount += 1
            }
            return registeredCount
        }
    }

    // MARK: - 合并

    func snapshots(
        for identities: [HistoryEntryIdentity]
    ) throws -> [HistoryEntryIdentity: HistoryEntrySyncLocalSnapshot] {
        let userID: String = self.currentUserID
        return try self.database.queue.read { database in
            var snapshots: [HistoryEntryIdentity: HistoryEntrySyncLocalSnapshot] = [:]
            for identity: HistoryEntryIdentity in Set(identities) {
                if let entry: HistorySyncLedgerRecord = try Self.ledgerEntry(identity, userID: userID, in: database) {
                    snapshots[identity] = HistoryEntrySyncLocalSnapshot(
                        identity: identity,
                        lastChangedAt: entry.changedAt,
                        isDeleted: entry.deletedAt != nil
                    )
                } else if let rowTime: Date = try Self.rowTime(identity, userID: userID, in: database) {
                    snapshots[identity] = HistoryEntrySyncLocalSnapshot(
                        identity: identity,
                        lastChangedAt: rowTime,
                        isDeleted: false
                    )
                }
            }
            return snapshots
        }
    }

    func availableSourceIDs(among sourceIDs: Set<String>) throws -> Set<String> {
        let userID: String = self.currentUserID
        return try self.database.queue.read { database in
            return try Self.availableSourceIDs(among: sourceIDs, userID: userID, in: database)
        }
    }

    func commit(_ plan: HistoryEntrySyncMergePlan, accountScope: CloudAccountScope) throws {
        let userID: String = self.currentUserID
        try self.database.queue.write { database in
            try AppUserRecord.insertUser(id: userID, in: database)
            for payload: HistoryEntryCloudPayload in plan.acceptedPayloads {
                let identity: HistoryEntryIdentity = payload.identity
                if let deletedAt: Date = payload.deletedAt {
                    try Self.deleteRows(identity, userID: userID, in: database)
                    try Self.saveLedger(
                        identity,
                        userID: userID,
                        changedAt: payload.lastChangedAt,
                        deletedAt: deletedAt,
                        in: database
                    )
                } else {
                    guard try Self.writeRows(payload, userID: userID, in: database) else {
                        continue
                    }
                    // 中文注释：账本时间不早于刚写进去的行时间，下一轮对比才不会把这次下载当成本机改动再传回去。
                    let rowTime: Date = try Self.rowTime(identity, userID: userID, in: database) ?? payload.lastChangedAt
                    try Self.saveLedger(
                        identity,
                        userID: userID,
                        changedAt: max(payload.lastChangedAt, rowTime),
                        deletedAt: nil,
                        in: database
                    )
                }
                // 云端版本赢了：本机为同一部作品排着的上传作废。
                _ = try SyncQueueRecord.deleteOne(
                    database,
                    key: SyncQueueItem.makeID(
                        accountScope: accountScope,
                        entityType: .historyEntry,
                        entityID: identity.syncEntityID
                    )
                )
            }

            for identity: HistoryEntryIdentity in plan.requeuedIdentities {
                guard let entry: HistorySyncLedgerRecord = try Self.ledgerEntry(identity, userID: userID, in: database) else {
                    continue
                }
                try Self.enqueue(
                    identity,
                    operation: entry.deletedAt == nil ? .upsert : .delete,
                    updatedAt: entry.changedAt,
                    accountScope: accountScope,
                    in: database
                )
            }
        }
    }

    // MARK: - 上传

    func pendingUploads(accountScope: CloudAccountScope) throws -> [HistoryEntrySyncPendingUpload] {
        let userID: String = self.currentUserID
        return try self.database.queue.read { database in
            let now: Date = self.now()
            let queueRecords: [SyncQueueRecord] = try SyncQueueRecord
                .filter(SyncQueueRecord.Columns.accountScope == accountScope.rawValue)
                .filter(SyncQueueRecord.Columns.entityType == SyncEntityType.historyEntry.rawValue)
                .filter(
                    SyncQueueRecord.Columns.nextRetryAt == nil ||
                        SyncQueueRecord.Columns.nextRetryAt <= now
                )
                .fetchAll(database)

            return try queueRecords.map { queueRecord in
                let payload: HistoryEntryCloudPayload?
                if let identity: HistoryEntryIdentity = HistoryEntryIdentity(syncEntityID: queueRecord.entityID) {
                    payload = try Self.uploadPayload(identity, userID: userID, in: database)
                } else {
                    payload = nil
                }
                return HistoryEntrySyncPendingUpload(
                    queueItem: queueRecord.domainModel(),
                    payload: payload
                )
            }
        }
    }

    func removePendingUploads(acknowledgements: [SyncQueueAcknowledgement]) throws {
        try self.database.queue.write { database in
            for acknowledgement: SyncQueueAcknowledgement in acknowledgements {
                guard let record: SyncQueueRecord = try SyncQueueRecord.fetchOne(
                    database,
                    key: acknowledgement.id
                ),
                record.operation == acknowledgement.operation.rawValue,
                record.updatedAt == acknowledgement.updatedAt else {
                    continue
                }
                _ = try SyncQueueRecord.deleteOne(database, key: acknowledgement.id)
            }
        }
    }

    func markPendingUploadsFailed(_ updates: [SyncQueueFailureUpdate]) throws {
        try self.database.queue.write { database in
            let failedAt: Date = self.now()
            for update: SyncQueueFailureUpdate in updates {
                let acknowledgement: SyncQueueAcknowledgement = update.acknowledgement
                guard var record: SyncQueueRecord = try SyncQueueRecord.fetchOne(
                    database,
                    key: acknowledgement.id
                ),
                record.operation == acknowledgement.operation.rawValue,
                record.updatedAt == acknowledgement.updatedAt else {
                    continue
                }
                record.retryCount += 1
                record.lastError = update.errorMessage
                record.nextRetryAt = update.retryAfter.flatMap { retryAfter in
                    CloudSyncAutomaticRetryPolicy.delay(
                        forFailureCount: record.retryCount,
                        serverRetryAfter: retryAfter
                    ).map {
                        failedAt.addingTimeInterval($0)
                    }
                }
                try record.save(database)
            }
        }
    }

    func syncedWorkCount() throws -> Int {
        let userID: String = self.currentUserID
        return try self.database.queue.read { database in
            let liveTimes: [HistoryEntryIdentity: Date] = try Self.liveWorkTimes(userID: userID, in: database)
            let availableSourceIDs: Set<String> = try Self.availableSourceIDs(
                among: Set(liveTimes.keys.map(\.sourceID)),
                userID: userID,
                in: database
            )
            return liveTimes.keys.filter { availableSourceIDs.contains($0.sourceID) }.count
        }
    }

    // MARK: - 历史表 → 作品

    /// 中文注释：每部作品一条及其改动时间。漫画按作品取最近一章的访问时间，视频取更新时间，书取访问时间。
    private static func liveWorkTimes(
        userID: String,
        in database: Database
    ) throws -> [HistoryEntryIdentity: Date] {
        var times: [HistoryEntryIdentity: Date] = [:]
        let comicRows: [Row] = try Row.fetchAll(
            database,
            sql: """
            SELECT sourceID, comicItemID AS workKey, MAX(visitedAt) AS changedAt
            FROM comic_chapter_history WHERE userID = ? GROUP BY sourceID, comicItemID
            """,
            arguments: [userID]
        )
        let videoRows: [Row] = try Row.fetchAll(
            database,
            sql: "SELECT sourceID, workKey, updatedAt AS changedAt FROM video_watch_history WHERE userID = ?",
            arguments: [userID]
        )
        let bookRows: [Row] = try Row.fetchAll(
            database,
            sql: "SELECT sourceID, detailURL AS workKey, visitedAt AS changedAt FROM book_reading_history WHERE userID = ?",
            arguments: [userID]
        )
        let grouped: [(HistoryEntryKind, [Row])] = [(.comic, comicRows), (.video, videoRows), (.book, bookRows)]
        for (kind, rows): (HistoryEntryKind, [Row]) in grouped {
            for row: Row in rows {
                guard let changedAt: Date = row["changedAt"] else {
                    continue
                }
                let identity: HistoryEntryIdentity = HistoryEntryIdentity(
                    kind: kind.rawValue,
                    sourceID: row["sourceID"],
                    workKey: row["workKey"]
                )
                times[identity] = changedAt
            }
        }
        return times
    }

    private static func rowTime(
        _ identity: HistoryEntryIdentity,
        userID: String,
        in database: Database
    ) throws -> Date? {
        guard let kind: HistoryEntryKind = HistoryEntryKind(rawValue: identity.kind) else {
            return nil
        }
        let sql: String
        switch kind {
        case .comic:
            sql = "SELECT MAX(visitedAt) FROM comic_chapter_history WHERE userID = ? AND sourceID = ? AND comicItemID = ?"
        case .video:
            sql = "SELECT updatedAt FROM video_watch_history WHERE userID = ? AND sourceID = ? AND workKey = ?"
        case .book:
            sql = "SELECT visitedAt FROM book_reading_history WHERE userID = ? AND sourceID = ? AND detailURL = ?"
        }
        return try Date.fetchOne(database, sql: sql, arguments: [userID, identity.sourceID, identity.workKey])
    }

    private static func availableSourceIDs(
        among sourceIDs: Set<String>,
        userID: String,
        in database: Database
    ) throws -> Set<String> {
        guard sourceIDs.isEmpty == false else {
            return []
        }
        let stored: [String] = try String.fetchAll(
            database,
            SourceRecord
                .select(SourceRecord.Columns.id)
                .filter(SourceRecord.Columns.userID == userID)
                .filter(SourceRecord.Columns.deletedAt == nil)
                .filter(sourceIDs.contains(SourceRecord.Columns.id))
        )
        // 中文注释：内置来源每台设备自带，不看表里有没有。
        return Set(stored).union(sourceIDs.filter { $0.hasPrefix("built-in.") })
    }

    // MARK: - 上传载荷

    private static func uploadPayload(
        _ identity: HistoryEntryIdentity,
        userID: String,
        in database: Database
    ) throws -> HistoryEntryCloudPayload? {
        let entry: HistorySyncLedgerRecord? = try Self.ledgerEntry(identity, userID: userID, in: database)
        if let entry: HistorySyncLedgerRecord, let deletedAt: Date = entry.deletedAt {
            return HistoryEntryCloudPayload.tombstone(identity: identity, deletedAt: deletedAt)
        }
        guard let kind: HistoryEntryKind = HistoryEntryKind(rawValue: identity.kind) else {
            return nil
        }
        var payload: HistoryEntryCloudPayload = HistoryEntryCloudPayload(
            schemaVersion: HistoryEntryCloudPayload.currentSchemaVersion,
            kind: identity.kind,
            sourceID: identity.sourceID,
            workKey: identity.workKey,
            updatedAt: entry?.changedAt ?? .distantPast
        )
        let key: StatementArguments = [userID, identity.sourceID, identity.workKey]

        switch kind {
        case .comic:
            guard let row: Row = try Row.fetchOne(
                database,
                sql: """
                SELECT comicTitle, chapterKey, chapterURL, chapterTitle, visitedAt, coverURL, lastPageIndex
                FROM comic_chapter_history WHERE userID = ? AND sourceID = ? AND comicItemID = ?
                ORDER BY visitedAt DESC LIMIT 1
                """,
                arguments: key
            ) else {
                return nil
            }
            payload.title = row["comicTitle"]
            payload.unitKey = row["chapterKey"]
            payload.unitURL = row["chapterURL"]
            payload.unitTitle = row["chapterTitle"]
            payload.coverURL = row["coverURL"]
            payload.pageIndex = row["lastPageIndex"]
            payload.visitedAt = row["visitedAt"]

        case .video:
            guard let row: Row = try Row.fetchOne(
                database,
                sql: """
                SELECT vodID, videoTitle, episodeTitle, episodeKey, sourceIndex, episodeIndex, detailURL,
                       playPageURL, coverURL, lastPlaybackTime, duration, visitedAt
                FROM video_watch_history WHERE userID = ? AND sourceID = ? AND workKey = ?
                """,
                arguments: key
            ) else {
                return nil
            }
            payload.itemID = row["vodID"]
            payload.title = row["videoTitle"]
            payload.unitTitle = row["episodeTitle"]
            payload.unitKey = row["episodeKey"]
            payload.sourceIndex = row["sourceIndex"]
            payload.episodeIndex = row["episodeIndex"]
            payload.detailURL = row["detailURL"]
            payload.unitURL = row["playPageURL"]
            payload.coverURL = row["coverURL"]
            payload.playbackTime = row["lastPlaybackTime"]
            payload.duration = row["duration"]
            payload.visitedAt = row["visitedAt"]

        case .book:
            guard let row: Row = try Row.fetchOne(
                database,
                sql: """
                SELECT bookItemID, bookTitle, coverURL, chapterTitle, chapterURL, visitedAt
                FROM book_reading_history WHERE userID = ? AND sourceID = ? AND detailURL = ?
                """,
                arguments: key
            ) else {
                return nil
            }
            payload.itemID = row["bookItemID"]
            payload.title = row["bookTitle"]
            payload.coverURL = row["coverURL"]
            payload.unitTitle = row["chapterTitle"]
            payload.unitURL = row["chapterURL"]
            payload.detailURL = identity.workKey
            payload.visitedAt = row["visitedAt"]
            if let progress: Row = try Row.fetchOne(
                database,
                sql: "SELECT locatorJSON, totalProgression FROM book_reading_progress WHERE bookID = ? AND userID = ?",
                arguments: [Self.siteBookID(identity), userID]
            ) {
                payload.locatorJSON = progress["locatorJSON"]
                payload.totalProgression = progress["totalProgression"]
            }
        }

        if entry == nil, let visitedAt: Date = payload.visitedAt {
            payload.updatedAt = visitedAt
        }
        return payload
    }

    // MARK: - 写入与删除历史行

    /// 中文注释：把云端记录写成对应历史表的一行；没上云的字段留空，打开时按规则重新取。写不了（类型不认识、缺必需字段）返回 false。
    private static func writeRows(
        _ payload: HistoryEntryCloudPayload,
        userID: String,
        in database: Database
    ) throws -> Bool {
        guard let kind: HistoryEntryKind = HistoryEntryKind(rawValue: payload.kind) else {
            return false
        }
        let visitedAt: Date = payload.visitedAt ?? payload.updatedAt

        switch kind {
        case .comic:
            guard let chapterKey: String = payload.unitKey, chapterKey.isEmpty == false else {
                return false
            }
            // 页码变了时，本机留着的「上次那一页」的地址与缓存键已经不对，清掉。
            try database.execute(
                sql: """
                INSERT INTO comic_chapter_history
                    (userID, sourceID, comicItemID, comicTitle, chapterKey, chapterURL, chapterTitle, visitedAt, coverURL, lastPageIndex)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(userID, sourceID, comicItemID, chapterKey) DO UPDATE SET
                    comicTitle = excluded.comicTitle,
                    chapterURL = COALESCE(excluded.chapterURL, chapterURL),
                    chapterTitle = excluded.chapterTitle,
                    visitedAt = excluded.visitedAt,
                    coverURL = COALESCE(excluded.coverURL, coverURL),
                    lastReaderPageURL = CASE WHEN lastPageIndex IS excluded.lastPageIndex THEN lastReaderPageURL ELSE NULL END,
                    lastPageImageURL = CASE WHEN lastPageIndex IS excluded.lastPageIndex THEN lastPageImageURL ELSE NULL END,
                    lastPageImageCacheKey = CASE WHEN lastPageIndex IS excluded.lastPageIndex THEN lastPageImageCacheKey ELSE NULL END,
                    lastPageIndex = excluded.lastPageIndex
                """,
                arguments: [
                    userID, payload.sourceID, payload.workKey, payload.title ?? "", chapterKey,
                    payload.unitURL, payload.unitTitle ?? "", visitedAt, payload.coverURL, payload.pageIndex
                ]
            )

        case .video:
            guard let playPageURL: String = payload.unitURL, playPageURL.isEmpty == false else {
                return false
            }
            let episodeKey: String = payload.unitKey ?? ""
            let sourceIndex: Int = payload.sourceIndex ?? 0
            let episodeIndex: Int = payload.episodeIndex ?? 0
            let existing: Row? = try Row.fetchOne(
                database,
                sql: """
                SELECT episodeKey, sourceIndex, episodeIndex FROM video_watch_history
                WHERE userID = ? AND sourceID = ? AND workKey = ?
                """,
                arguments: [userID, payload.sourceID, payload.workKey]
            )
            let isSameEpisode: Bool = existing.map { row in
                let existingEpisodeKey: String = row["episodeKey"]
                let existingSourceIndex: Int = row["sourceIndex"]
                let existingEpisodeIndex: Int = row["episodeIndex"]
                return existingEpisodeKey == episodeKey &&
                    existingSourceIndex == sourceIndex &&
                    existingEpisodeIndex == episodeIndex
            } ?? false

            if isSameEpisode {
                // 同一集：只更新进度与时间，本机已解析好的播放地址留着。
                try database.execute(
                    sql: """
                    UPDATE video_watch_history
                    SET lastPlaybackTime = ?, duration = COALESCE(?, duration), visitedAt = ?, updatedAt = ?
                    WHERE userID = ? AND sourceID = ? AND workKey = ?
                    """,
                    arguments: [
                        payload.playbackTime ?? 0, payload.duration, visitedAt, payload.updatedAt,
                        userID, payload.sourceID, payload.workKey
                    ]
                )
            } else {
                try database.execute(
                    sql: "DELETE FROM video_watch_history WHERE userID = ? AND sourceID = ? AND workKey = ?",
                    arguments: [userID, payload.sourceID, payload.workKey]
                )
                try database.execute(
                    sql: """
                    INSERT INTO video_watch_history
                        (userID, sourceID, vodID, workKey, videoTitle, episodeTitle, episodeKey, sourceIndex, episodeIndex,
                         detailURL, playPageURL, candidateMediaKind, coverURL, lastPlaybackTime, duration, visitedAt, updatedAt)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        userID, payload.sourceID, Self.vodID(payload), payload.workKey, payload.title ?? "",
                        payload.unitTitle, episodeKey, sourceIndex, episodeIndex,
                        payload.detailURL, playPageURL, "unknown", payload.coverURL,
                        payload.playbackTime ?? 0, payload.duration, visitedAt, payload.updatedAt
                    ]
                )
            }

        case .book:
            try database.execute(
                sql: """
                INSERT INTO book_reading_history
                    (userID, sourceID, detailURL, bookItemID, bookTitle, coverURL, chapterTitle, chapterURL, visitedAt)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(userID, sourceID, detailURL) DO UPDATE SET
                    bookItemID = excluded.bookItemID,
                    bookTitle = excluded.bookTitle,
                    coverURL = COALESCE(excluded.coverURL, coverURL),
                    chapterTitle = excluded.chapterTitle,
                    chapterURL = excluded.chapterURL,
                    visitedAt = excluded.visitedAt
                """,
                arguments: [
                    userID, payload.sourceID, payload.workKey, payload.itemID ?? payload.workKey,
                    payload.title ?? "", payload.coverURL, payload.unitTitle, payload.unitURL, visitedAt
                ]
            )
            if let locatorJSON: String = payload.locatorJSON, locatorJSON.isEmpty == false {
                try database.execute(
                    sql: """
                    INSERT INTO book_reading_progress (bookID, userID, locatorJSON, totalProgression, updatedAt)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(bookID, userID) DO UPDATE SET
                        locatorJSON = excluded.locatorJSON,
                        totalProgression = excluded.totalProgression,
                        updatedAt = excluded.updatedAt
                    """,
                    arguments: [
                        Self.siteBookID(payload.identity), userID, locatorJSON,
                        payload.totalProgression, payload.updatedAt
                    ]
                )
            }
        }
        return true
    }

    /// 中文注释：与本机删除历史一致——只删历史行；书的续读位置不随历史删除。
    private static func deleteRows(
        _ identity: HistoryEntryIdentity,
        userID: String,
        in database: Database
    ) throws {
        guard let kind: HistoryEntryKind = HistoryEntryKind(rawValue: identity.kind) else {
            return
        }
        let sql: String
        switch kind {
        case .comic:
            sql = "DELETE FROM comic_chapter_history WHERE userID = ? AND sourceID = ? AND comicItemID = ?"
        case .video:
            sql = "DELETE FROM video_watch_history WHERE userID = ? AND sourceID = ? AND workKey = ?"
        case .book:
            sql = "DELETE FROM book_reading_history WHERE userID = ? AND sourceID = ? AND detailURL = ?"
        }
        try database.execute(sql: sql, arguments: [userID, identity.sourceID, identity.workKey])
    }

    private static func vodID(_ payload: HistoryEntryCloudPayload) -> String {
        if let itemID: String = payload.itemID, itemID.isEmpty == false {
            return itemID
        }
        let prefix: String = "vod::"
        return payload.workKey.hasPrefix(prefix) ? String(payload.workKey.dropFirst(prefix.count)) : ""
    }

    private static func siteBookID(_ identity: HistoryEntryIdentity) -> String {
        return SiteBookIdentity.bookID(sourceID: identity.sourceID, detailURL: identity.workKey).uuidString
    }

    // MARK: - 账本与队列

    private static func ledgerEntry(
        _ identity: HistoryEntryIdentity,
        userID: String,
        in database: Database
    ) throws -> HistorySyncLedgerRecord? {
        return try HistorySyncLedgerRecord.fetchOne(
            database,
            key: [
                "userID": userID,
                "kind": identity.kind,
                "sourceID": identity.sourceID,
                "workKey": identity.workKey
            ]
        )
    }

    private static func saveLedger(
        _ identity: HistoryEntryIdentity,
        userID: String,
        changedAt: Date,
        deletedAt: Date?,
        in database: Database
    ) throws {
        var record: HistorySyncLedgerRecord = HistorySyncLedgerRecord(
            userID: userID,
            kind: identity.kind,
            sourceID: identity.sourceID,
            workKey: identity.workKey,
            changedAt: changedAt,
            deletedAt: deletedAt
        )
        try record.save(database)
    }

    private static func enqueue(
        _ identity: HistoryEntryIdentity,
        operation: SyncQueueOperation,
        updatedAt: Date,
        accountScope: CloudAccountScope,
        in database: Database
    ) throws {
        try SyncQueueRecord.enqueue(
            accountScope: accountScope,
            entityType: .historyEntry,
            entityID: identity.syncEntityID,
            operation: operation,
            updatedAt: updatedAt,
            in: database
        )
    }

    private var currentUserID: String {
        if let synchronizedUserID: UUID = self.userContext?.currentUserID {
            return synchronizedUserID.uuidString
        }
        return self.activeAppUser?.currentUserID.uuidString ?? AppUser.localDefaultID
    }
}
