import BrowseCraftCore
import BrowseCraftDomain
import Foundation
import GRDB
import Testing
@testable import BrowseCraft

// 中文注释：v6.remove-rss 在真实迁移链上的固定输入——先迁到 v5 写入 RSS 时代的数据，再迁到最新：
// RSS 来源及其同步队列项清掉、RSS 历史表删掉；书籍收藏（此前被记成 rss）改记 book 保留，其余 rss 收藏清掉；收藏聚合随之重建。
struct RemoveRSSMigrationTests {
    private static let userID: String = "u1"
    private static let now: Date = Date(timeIntervalSince1970: 1_789_300_000)

    @Test func rssDataIsRemovedAndBookFavoritesSurviveAsBook() throws {
        let path: String = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrowseCraftRemoveRSSMigrationTests-\(UUID().uuidString).sqlite")
            .path
        let queue: DatabaseQueue = try DatabaseQueue(path: path)
        let migrator: DatabaseMigrator = AppDatabaseMigrations.makeMigrator()
        try migrator.migrate(queue, upTo: AppDatabaseMigrations.bookReadingHistoryIdentifier)

        var bookSource: Source = try ViewModelTestHarness.makeBookSource()
        bookSource.userID = Self.userID
        let bookFavorite: FavoriteContentItem = Self.favorite(id: "book-item", sourceID: bookSource.id, kind: .book)
        let feedFavorite: FavoriteContentItem = Self.favorite(id: "feed-item", sourceID: "rss.gcores", kind: .comic)
        let bookFavoriteSyncID: String = FavoriteItemIdentity(sourceID: bookSource.id, itemID: "book-item").syncEntityID
        let feedFavoriteSyncID: String = FavoriteItemIdentity(sourceID: "rss.gcores", itemID: "feed-item").syncEntityID

        try queue.write { database in
            try AppUserRecord.insertUser(id: Self.userID, in: database)
            var bookRecord: SourceRecord = try SourceRecord(source: bookSource)
            try bookRecord.insert(database)
            try database.execute(
                sql: """
                INSERT INTO sources (userID, id, name, baseURL, type, kind, configJSON, enabled, createdAt, updatedAt)
                VALUES (?, 'rss.gcores', '机核', 'https://www.gcores.com', 'rss', 'rss', '{"rss":{}}', 1, ?, ?)
                """,
                arguments: [Self.userID, Self.now, Self.now]
            )
            for item: FavoriteContentItem in [bookFavorite, feedFavorite] {
                var record: FavoriteItemRecord = try FavoriteItemRecord(
                    userID: Self.userID,
                    item: item,
                    updatedAt: Self.now,
                    deletedAt: nil
                )
                try record.insert(database)
            }
            try FavoriteAggregateBuilder.rebuild(userID: Self.userID, in: database)
            // 中文注释：还原 RSS 下线前的形状——书籍条目是 article 形态，被记成 rss 收藏（列与 itemJSON 里都是 rss）。
            try database.execute(
                sql: """
                UPDATE favorite_items
                SET kind = 'rss',
                    itemJSON = replace(replace(itemJSON, '"kind":"book"', '"kind":"rss"'), '"kind":"comic"', '"kind":"rss"')
                """
            )
            for (entityType, entityID) in [("source", "rss.gcores"), ("favoriteItem", feedFavoriteSyncID), ("favoriteItem", bookFavoriteSyncID)] {
                try database.execute(
                    sql: """
                    INSERT INTO sync_queue (id, accountScope, entityType, entityID, operation, updatedAt, createdAt)
                    VALUES (?, 'local', ?, ?, 'upsert', ?, ?)
                    """,
                    arguments: [UUID().uuidString, entityType, entityID, Self.now, Self.now]
                )
            }
        }
        let legacyKinds: [String] = try queue.read { database in
            try String.fetchAll(database, sql: "SELECT DISTINCT kind FROM favorite_items")
        }
        let legacyItemJSON: [String] = try queue.read { database in
            try String.fetchAll(database, sql: "SELECT itemJSON FROM favorite_items")
        }
        #expect(legacyKinds == ["rss"])
        #expect(legacyItemJSON.count == 2)
        #expect(legacyItemJSON.allSatisfy { json in json.contains("\"kind\":\"rss\"") })

        try migrator.migrate(queue)

        let sourceIDs: [String] = try queue.read { database in
            try String.fetchAll(database, sql: "SELECT id FROM sources")
        }
        let decodedSources: [Source] = try queue.read { database in
            try SourceRecord.fetchAll(database).map { record in try record.domainModel() }
        }
        let historyTableExists: Bool = try queue.read { database in
            try database.tableExists("rss_reading_history")
        }
        let favorites: [FavoriteItemRecord] = try queue.read { database in
            try FavoriteItemRecord.fetchAll(database)
        }
        let queuedEntityIDs: [String] = try queue.read { database in
            try String.fetchAll(database, sql: "SELECT entityID FROM sync_queue")
        }
        let aggregate: FavoriteRecord? = try queue.read { database in
            try FavoriteRecord.fetchOne(database, key: Self.userID)
        }

        #expect(sourceIDs == [bookSource.id])
        #expect(decodedSources.map(\.id) == [bookSource.id])
        #expect(historyTableExists == false)
        #expect(favorites.map(\.itemID) == ["book-item"])
        #expect(favorites.first?.kind == "book")
        #expect(favorites.first?.favoriteItem()?.kind == .book)
        #expect(queuedEntityIDs == [bookFavoriteSyncID])
        let aggregateJSON: String = try #require(aggregate?.favoriteItemsJSON)
        #expect(aggregateJSON.contains("book-item"))
        #expect(aggregateJSON.contains("feed-item") == false)
    }

    private static func favorite(id: String, sourceID: String, kind: FavoriteContentKind) -> FavoriteContentItem {
        return FavoriteContentItem(
            id: id,
            sourceID: sourceID,
            title: "Favorite \(id)",
            detailURL: "https://example.test/\(id)",
            coverURL: nil,
            kind: kind,
            latestText: nil,
            updatedAt: Self.now,
            favoritedAt: Self.now,
            listOrder: nil,
            listContext: nil,
            sourceSnapshot: nil
        )
    }
}
