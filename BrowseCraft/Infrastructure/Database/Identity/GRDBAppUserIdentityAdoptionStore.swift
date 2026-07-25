import Foundation
import GRDB

/// 中文注释：采用 B 时复制 A 的本地业务内容并保留 A；不复制 AppUser 权益字段或 StoreKit 交易。
final class GRDBAppUserIdentityAdoptionStore:
    AppUserIdentityAdoptionStoring,
    @unchecked Sendable {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func summary(for userID: UUID) throws -> AppUserIdentityLocalDataSummary {
        let databaseUserID: String = userID.uuidString
        return try self.database.queue.read { database in
            let sourceRecords: [SourceRecord] = try SourceRecord
                .filter(SourceRecord.Columns.userID == databaseUserID)
                .fetchAll(database)
            let favoriteItemCount: Int = try FavoriteItemRecord
                .filter(FavoriteItemRecord.Columns.userID == databaseUserID)
                .fetchCount(database)
            let rssHistoryCount: Int = try RSSReadingHistoryRecord
                .filter(RSSReadingHistoryRecord.Columns.userID == databaseUserID)
                .fetchCount(database)
            let comicHistoryCount: Int = try ComicChapterHistoryRecord
                .filter(ComicChapterHistoryRecord.Columns.userID == databaseUserID)
                .fetchCount(database)
            let videoHistoryCount: Int = try VideoWatchHistoryRecord
                .filter(VideoWatchHistoryRecord.Columns.userID == databaseUserID)
                .fetchCount(database)
            let historyCount: Int =
                rssHistoryCount + comicHistoryCount + videoHistoryCount
            let temporaryResourceCount: Int = try TemporaryResourceHistoryRecord
                .filter(TemporaryResourceHistoryRecord.Columns.userID == databaseUserID)
                .fetchCount(database)
            let libraryState: UserLibraryStateRecord? = try UserLibraryStateRecord.fetchOne(
                database,
                key: databaseUserID
            )
            let hasLibraryState: Bool =
                libraryState?.selectedSourceID != nil ||
                libraryState?.listContextJSON != nil ||
                libraryState?.lastRefreshAt != nil

            return AppUserIdentityLocalDataSummary(
                sourceCount: sourceRecords.filter { record in
                    return record.id.hasPrefix("built-in.") == false
                }.count,
                favoriteItemCount: favoriteItemCount,
                historyCount: historyCount,
                temporaryResourceCount: temporaryResourceCount,
                hasLibraryState: hasLibraryState
            )
        }
    }

    func prepareAdoption(
        from localUserID: UUID,
        to cloudUserID: UUID,
        decision: CloudAccountLocalDataDecision
    ) throws -> AppUserIdentityAdoptionResult {
        let localID: String = localUserID.uuidString
        let cloudID: String = cloudUserID.uuidString

        return try self.database.queue.write { database in
            try AppUserRecord.insertUser(id: cloudID, in: database)

            guard decision == .mergeLocalData,
                  localID != cloudID else {
                return AppUserIdentityAdoptionResult(
                    copiedSourceCount: 0,
                    copiedFavoriteItemCount: 0,
                    copiedHistoryCount: 0,
                    copiedTemporaryResourceCount: 0,
                    copiedLibraryState: false
                )
            }

            let copiedSourceCount: Int = try Self.copySources(
                from: localID,
                to: cloudID,
                in: database
            )
            let copiedFavoriteItemCount: Int = try Self.copyFavoriteItems(
                from: localID,
                to: cloudID,
                in: database
            )
            let copiedRSSHistoryCount: Int = try Self.copyRSSHistory(
                from: localID,
                to: cloudID,
                in: database
            )
            let copiedComicHistoryCount: Int = try Self.copyComicHistory(
                from: localID,
                to: cloudID,
                in: database
            )
            let copiedVideoHistoryCount: Int = try Self.copyVideoHistory(
                from: localID,
                to: cloudID,
                in: database
            )
            let copiedHistoryCount: Int =
                copiedRSSHistoryCount +
                copiedComicHistoryCount +
                copiedVideoHistoryCount
            let copiedTemporaryResourceCount: Int = try Self.copyTemporaryHistory(
                from: localID,
                to: cloudID,
                in: database
            )
            let copiedLibraryState: Bool = try Self.copyLibraryState(
                from: localID,
                to: cloudID,
                in: database
            )

            try FavoriteAggregateBuilder.rebuild(userID: cloudID, in: database)
            return AppUserIdentityAdoptionResult(
                copiedSourceCount: copiedSourceCount,
                copiedFavoriteItemCount: copiedFavoriteItemCount,
                copiedHistoryCount: copiedHistoryCount,
                copiedTemporaryResourceCount: copiedTemporaryResourceCount,
                copiedLibraryState: copiedLibraryState
            )
        }
    }

    private static func copySources(
        from localID: String,
        to cloudID: String,
        in database: Database
    ) throws -> Int {
        let records: [SourceRecord] = try SourceRecord
            .filter(SourceRecord.Columns.userID == localID)
            .fetchAll(database)
        var copiedCount: Int = 0

        for var record: SourceRecord in records {
            let key: [String: String] = ["userID": cloudID, "id": record.id]
            if let existing: SourceRecord = try SourceRecord.fetchOne(database, key: key),
               existing.lastChangedAt >= record.lastChangedAt {
                continue
            }
            record.userID = cloudID
            try record.save(database)
            copiedCount += 1
        }
        return copiedCount
    }

    private static func copyFavoriteItems(
        from localID: String,
        to cloudID: String,
        in database: Database
    ) throws -> Int {
        let records: [FavoriteItemRecord] = try FavoriteItemRecord
            .filter(FavoriteItemRecord.Columns.userID == localID)
            .fetchAll(database)
        var copiedCount: Int = 0

        for var record: FavoriteItemRecord in records {
            let key: [String: String] = [
                "userID": cloudID,
                "sourceID": record.sourceID,
                "itemID": record.itemID
            ]
            if let existing: FavoriteItemRecord = try FavoriteItemRecord.fetchOne(
                database,
                key: key
            ), existing.lastChangedAt >= record.lastChangedAt {
                continue
            }
            record.userID = cloudID
            try record.save(database)
            copiedCount += 1
        }
        return copiedCount
    }

    private static func copyRSSHistory(
        from localID: String,
        to cloudID: String,
        in database: Database
    ) throws -> Int {
        let records: [RSSReadingHistoryRecord] = try RSSReadingHistoryRecord
            .filter(RSSReadingHistoryRecord.Columns.userID == localID)
            .fetchAll(database)
        var copiedCount: Int = 0

        for var record: RSSReadingHistoryRecord in records {
            let key: [String: String] = [
                "userID": cloudID,
                "sourceID": record.sourceID,
                "itemID": record.itemID
            ]
            if let existing: RSSReadingHistoryRecord = try RSSReadingHistoryRecord.fetchOne(
                database,
                key: key
            ), existing.visitedAt >= record.visitedAt {
                continue
            }
            _ = try RSSReadingHistoryRecord
                .filter(RSSReadingHistoryRecord.Columns.userID == cloudID)
                .filter(RSSReadingHistoryRecord.Columns.sourceID == record.sourceID)
                .filter(RSSReadingHistoryRecord.Columns.itemID == record.itemID)
                .deleteAll(database)
            record.userID = cloudID
            try record.insert(database)
            copiedCount += 1
        }
        return copiedCount
    }

    private static func copyComicHistory(
        from localID: String,
        to cloudID: String,
        in database: Database
    ) throws -> Int {
        let records: [ComicChapterHistoryRecord] = try ComicChapterHistoryRecord
            .filter(ComicChapterHistoryRecord.Columns.userID == localID)
            .fetchAll(database)
        var copiedCount: Int = 0

        for var record: ComicChapterHistoryRecord in records {
            let key: [String: String] = [
                "userID": cloudID,
                "sourceID": record.sourceID,
                "comicItemID": record.comicItemID,
                "chapterKey": record.chapterKey
            ]
            if let existing: ComicChapterHistoryRecord = try ComicChapterHistoryRecord.fetchOne(
                database,
                key: key
            ), existing.visitedAt >= record.visitedAt {
                continue
            }
            _ = try ComicChapterHistoryRecord
                .filter(ComicChapterHistoryRecord.Columns.userID == cloudID)
                .filter(ComicChapterHistoryRecord.Columns.sourceID == record.sourceID)
                .filter(
                    ComicChapterHistoryRecord.Columns.comicItemID ==
                        record.comicItemID
                )
                .filter(ComicChapterHistoryRecord.Columns.chapterKey == record.chapterKey)
                .deleteAll(database)
            record.userID = cloudID
            try record.insert(database)
            copiedCount += 1
        }
        return copiedCount
    }

    private static func copyVideoHistory(
        from localID: String,
        to cloudID: String,
        in database: Database
    ) throws -> Int {
        let records: [VideoWatchHistoryRecord] = try VideoWatchHistoryRecord
            .filter(VideoWatchHistoryRecord.Columns.userID == localID)
            .fetchAll(database)
        var copiedCount: Int = 0

        for var record: VideoWatchHistoryRecord in records {
            let key: [String: String] = [
                "userID": cloudID,
                "sourceID": record.sourceID,
                "workKey": record.workKey
            ]
            if let existing: VideoWatchHistoryRecord = try VideoWatchHistoryRecord.fetchOne(
                database,
                key: key
            ), existing.updatedAt >= record.updatedAt {
                continue
            }
            _ = try VideoWatchHistoryRecord
                .filter(VideoWatchHistoryRecord.Columns.userID == cloudID)
                .filter(VideoWatchHistoryRecord.Columns.sourceID == record.sourceID)
                .filter(VideoWatchHistoryRecord.Columns.workKey == record.workKey)
                .deleteAll(database)
            record.userID = cloudID
            try record.insert(database)
            copiedCount += 1
        }
        return copiedCount
    }

    private static func copyTemporaryHistory(
        from localID: String,
        to cloudID: String,
        in database: Database
    ) throws -> Int {
        let records: [TemporaryResourceHistoryRecord] = try TemporaryResourceHistoryRecord
            .filter(TemporaryResourceHistoryRecord.Columns.userID == localID)
            .fetchAll(database)
        var copiedCount: Int = 0

        for var record: TemporaryResourceHistoryRecord in records {
            let key: [String: String] = [
                "userID": cloudID,
                "kind": record.kind,
                "resourceURL": record.resourceURL
            ]
            if let existing: TemporaryResourceHistoryRecord =
                try TemporaryResourceHistoryRecord.fetchOne(database, key: key),
               existing.visitedAt >= record.visitedAt {
                continue
            }
            _ = try TemporaryResourceHistoryRecord
                .filter(TemporaryResourceHistoryRecord.Columns.userID == cloudID)
                .filter(TemporaryResourceHistoryRecord.Columns.kind == record.kind)
                .filter(
                    TemporaryResourceHistoryRecord.Columns.resourceURL ==
                        record.resourceURL
                )
                .deleteAll(database)
            record.userID = cloudID
            try record.insert(database)
            copiedCount += 1
        }
        return copiedCount
    }

    private static func copyLibraryState(
        from localID: String,
        to cloudID: String,
        in database: Database
    ) throws -> Bool {
        guard var record: UserLibraryStateRecord = try UserLibraryStateRecord.fetchOne(
            database,
            key: localID
        ) else {
            return false
        }
        if let existing: UserLibraryStateRecord = try UserLibraryStateRecord.fetchOne(
            database,
            key: cloudID
        ), existing.updatedAt >= record.updatedAt {
            return false
        }
        record.userID = cloudID
        try record.save(database)
        return true
    }
}
