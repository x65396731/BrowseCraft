import BrowseCraftCore
import BrowseCraftDomain
import Foundation
import GRDB
import Testing
@testable import BrowseCraft

// 中文注释：v10.sources-add-catalog-rule-fingerprint 在真实迁移链上的固定输入（`BCA-DB-003`）：
// 先迁到 v9 写入一条来源，再迁到最新——列加上、旧行原样、指纹为 NULL、外键检查干净；全新库同样到位。
struct SourcesCatalogRuleFingerprintMigrationTests {
    private static let userID: String = "u1"

    @Test func upgradingFromV9KeepsSourcesAndAddsANullFingerprint() throws {
        let queue: DatabaseQueue = try Self.makeQueue()
        let migrator: DatabaseMigrator = AppDatabaseMigrations.makeMigrator()
        try migrator.migrate(queue, upTo: AppDatabaseMigrations.comicHistoryAddPageCountIdentifier)

        var source: Source = try ViewModelTestHarness.makeBookSource()
        source.userID = Self.userID
        try queue.write { database in
            try AppUserRecord.insertUser(id: Self.userID, in: database)
            try insertSourceRowAsOfV9(source, in: database)
        }
        let columnsBefore: [String] = try queue.read { database in
            try database.columns(in: "sources").map(\.name)
        }
        #expect(columnsBefore.contains("catalogRuleFingerprint") == false)

        try migrator.migrate(queue)

        try queue.read { database in
            let columns: [String] = try database.columns(in: "sources").map(\.name)
            #expect(columns.contains("catalogRuleFingerprint"))
            let record: SourceRecord? = try SourceRecord.fetchOne(database, key: ["userID": Self.userID, "id": source.id])
            #expect(record?.name == source.name)
            #expect(record?.catalogRuleFingerprint == nil)
            let violations: [Row] = try Row.fetchAll(database, sql: "PRAGMA foreign_key_check")
            #expect(violations.isEmpty)
        }
    }

    @Test func freshDatabaseHasTheFingerprintColumn() throws {
        let queue: DatabaseQueue = try Self.makeQueue()
        try AppDatabaseMigrations.makeMigrator().migrate(queue)
        let columns: [String] = try queue.read { database in
            try database.columns(in: "sources").map(\.name)
        }
        #expect(columns.contains("catalogRuleFingerprint"))
    }

    private static func makeQueue() throws -> DatabaseQueue {
        let path: String = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrowseCraftCatalogFingerprintMigrationTests-\(UUID().uuidString).sqlite")
            .path
        return try DatabaseQueue(path: path)
    }
}

// 中文注释：旧版 schema 上插来源行要按当时的列写 SQL——`SourceRecord` 带着后来迁移加的列（v10 的指纹），整条 insert 会撞上「no such column」。
func insertSourceRowAsOfV9(_ source: Source, in database: Database) throws {
    let record: SourceRecord = try SourceRecord(source: source)
    try database.execute(
        sql: """
        INSERT INTO sources (userID, id, name, baseURL, type, kind, configJSON, enabled, createdAt, updatedAt, deletedAt, origin)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        arguments: [record.userID, record.id, record.name, record.baseURL, record.type, record.kind, record.configJSON, record.enabled, record.createdAt, record.updatedAt, record.deletedAt, record.origin]
    )
}
