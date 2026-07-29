import Foundation
import GRDB
import Testing
@testable import BrowseCraft

struct AppDatabaseMigrationTests {
    @Test func freshDatabaseRecordsCurrentSchemaMigration() throws {
        let path: String = Self.temporaryDatabasePath()
        let database: AppDatabase = try AppDatabase(path: path)

        let identifiers: [String] = try database.queue.read { database in
            return try String.fetchAll(
                database,
                sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier"
            )
        }

        #expect(identifiers == [AppDatabase.currentSchemaMigrationIdentifier])
    }

    @Test func reopeningDatabaseIsIdempotentAndPreservesMigrationLedger() throws {
        let path: String = Self.temporaryDatabasePath()
        _ = try AppDatabase(path: path)
        let reopened: AppDatabase = try AppDatabase(path: path)

        let migrationCount: Int = try reopened.queue.read { database in
            return try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM grdb_migrations"
            ) ?? 0
        }

        #expect(migrationCount == 1)
    }

    private static func temporaryDatabasePath() -> String {
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("BrowseCraftMigrationTests-\(UUID().uuidString).sqlite")
            .path
    }
}
