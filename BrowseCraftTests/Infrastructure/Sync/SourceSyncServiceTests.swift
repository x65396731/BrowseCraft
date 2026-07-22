import Foundation
import Testing
import GRDB
import BrowseCraftCore
@testable import BrowseCraft

struct SourceSyncServiceTests {
    @Test func uploadsLocalSourceAndClearsQueue() throws {
        let database: AppDatabase = try Self.makeDatabase()
        let sourceRepository: GRDBSourceRepository = GRDBSourceRepository(database: database)
        let queueRepository: GRDBSyncQueueRepository = GRDBSyncQueueRepository(database: database)
        let cloudStore: MockCloudRecordStore = MockCloudRecordStore()
        let service: SourceSyncService = Self.makeService(database: database, cloudStore: cloudStore)

        try sourceRepository.saveSource(Self.makeRSSSource(id: "source-1", name: "Local Source", updatedAt: 100))

        let result: SourceSyncResult = try service.syncSources(limit: 10)

        #expect(result.uploadedCount == 1)
        #expect(cloudStore.sourceRecord(id: "source-1")?.payload.name == "Local Source")
        #expect(try queueRepository.fetchPending(limit: 10).isEmpty)
    }

    @Test func downloadsCloudSourceToLocalDatabase() throws {
        let database: AppDatabase = try Self.makeDatabase()
        let sourceRepository: GRDBSourceRepository = GRDBSourceRepository(database: database)
        let cloudStore: MockCloudRecordStore = MockCloudRecordStore(
            sourceRecords: [
                SourceCloudRecord(
                    payload: try Self.payload(id: "source-1", name: "Cloud Source", updatedAt: 100),
                    serverUpdatedAt: Date(timeIntervalSince1970: 110),
                    version: 1
                )
            ]
        )
        let service: SourceSyncService = Self.makeService(database: database, cloudStore: cloudStore)

        let result: SourceSyncResult = try service.syncSources(limit: 10)
        let sources: [Source] = try sourceRepository.fetchSources()

        #expect(result.downloadedCount == 1)
        #expect(sources.map(\.id) == ["source-1"])
        #expect(sources.first?.name == "Cloud Source")
    }

    @Test func uploadsLocalDeleteAsCloudTombstone() throws {
        let database: AppDatabase = try Self.makeDatabase()
        let sourceRepository: GRDBSourceRepository = GRDBSourceRepository(database: database)
        let cloudStore: MockCloudRecordStore = MockCloudRecordStore()
        let service: SourceSyncService = Self.makeService(database: database, cloudStore: cloudStore)

        try sourceRepository.saveSource(Self.makeRSSSource(id: "source-1", name: "Local Source", updatedAt: 100))
        try sourceRepository.deleteSource(id: "source-1")

        let result: SourceSyncResult = try service.syncSources(limit: 10)

        #expect(result.uploadedCount == 1)
        #expect(cloudStore.sourceRecord(id: "source-1")?.payload.deletedAt != nil)
    }

    @Test func cloudDeleteSoftDeletesLocalSource() throws {
        let database: AppDatabase = try Self.makeDatabase()
        try Self.insertSource(Self.makeRSSSource(id: "source-1", name: "Local Source", updatedAt: 100), into: database)
        let cloudStore: MockCloudRecordStore = MockCloudRecordStore(
            sourceRecords: [
                SourceCloudRecord(
                    payload: try Self.payload(
                        id: "source-1",
                        name: "Cloud Tombstone",
                        updatedAt: 100,
                        deletedAt: 200
                    ),
                    serverUpdatedAt: Date(timeIntervalSince1970: 210),
                    version: 1
                )
            ]
        )
        let service: SourceSyncService = Self.makeService(database: database, cloudStore: cloudStore)

        let result: SourceSyncResult = try service.syncSources(limit: 10)
        let visibleSources: [Source] = try GRDBSourceRepository(database: database).fetchSources()
        let deletedAt: Date? = try Self.sourceRecord(id: "source-1", in: database)?.deletedAt

        #expect(result.deletedCount == 1)
        #expect(visibleSources.isEmpty)
        #expect(deletedAt == Date(timeIntervalSince1970: 200))
    }

    @Test func newerLocalSourceWinsOverOlderCloudSource() throws {
        let database: AppDatabase = try Self.makeDatabase()
        try Self.insertSource(Self.makeRSSSource(id: "source-1", name: "Local New", updatedAt: 200), into: database)
        let cloudStore: MockCloudRecordStore = MockCloudRecordStore(
            sourceRecords: [
                SourceCloudRecord(
                    payload: try Self.payload(id: "source-1", name: "Cloud Old", updatedAt: 100),
                    serverUpdatedAt: Date(timeIntervalSince1970: 110),
                    version: 1
                )
            ]
        )
        let service: SourceSyncService = Self.makeService(database: database, cloudStore: cloudStore)

        let result: SourceSyncResult = try service.syncSources(limit: 10)

        #expect(result.skippedCount == 1)
        #expect(result.uploadedCount == 1)
        #expect(cloudStore.sourceRecord(id: "source-1")?.payload.name == "Local New")
    }

    @Test func newerCloudSourceWinsOverOlderLocalSource() throws {
        let database: AppDatabase = try Self.makeDatabase()
        try Self.insertSource(Self.makeRSSSource(id: "source-1", name: "Local Old", updatedAt: 100), into: database)
        let cloudStore: MockCloudRecordStore = MockCloudRecordStore(
            sourceRecords: [
                SourceCloudRecord(
                    payload: try Self.payload(id: "source-1", name: "Cloud New", updatedAt: 200),
                    serverUpdatedAt: Date(timeIntervalSince1970: 210),
                    version: 1
                )
            ]
        )
        let service: SourceSyncService = Self.makeService(database: database, cloudStore: cloudStore)

        _ = try service.syncSources(limit: 10)
        let source: Source? = try GRDBSourceRepository(database: database).fetchSources().first

        #expect(source?.name == "Cloud New")
    }

    @Test func uploadFailureKeepsQueueAndIncrementsRetryCount() throws {
        let database: AppDatabase = try Self.makeDatabase()
        let sourceRepository: GRDBSourceRepository = GRDBSourceRepository(database: database)
        let queueRepository: GRDBSyncQueueRepository = GRDBSyncQueueRepository(database: database)
        let cloudStore: MockCloudRecordStore = MockCloudRecordStore()
        cloudStore.failNextSave = true
        let service: SourceSyncService = Self.makeService(database: database, cloudStore: cloudStore)

        try sourceRepository.saveSource(Self.makeRSSSource(id: "source-1", name: "Local Source", updatedAt: 100))

        #expect(throws: MockCloudRecordStoreError.saveFailed) {
            _ = try service.syncSources(limit: 10)
        }
        let pending: [SyncQueueItem] = try queueRepository.fetchPending(limit: 10)

        #expect(pending.count == 1)
        #expect(pending[0].retryCount == 1)
        #expect(pending[0].lastError != nil)
    }

    @Test func temporaryInconsistencyConvergesAfterTombstoneUpload() throws {
        let initialPayload: SourceCloudPayload = try Self.payload(id: "source-1", name: "Cloud Source", updatedAt: 100)
        let cloudStore: MockCloudRecordStore = MockCloudRecordStore(
            sourceRecords: [
                SourceCloudRecord(
                    payload: initialPayload,
                    serverUpdatedAt: Date(timeIntervalSince1970: 110),
                    version: 1
                )
            ]
        )
        let deviceADatabase: AppDatabase = try Self.makeDatabase()
        let deviceBDatabase: AppDatabase = try Self.makeDatabase()
        let deviceAService: SourceSyncService = Self.makeService(database: deviceADatabase, cloudStore: cloudStore)
        let deviceBService: SourceSyncService = Self.makeService(database: deviceBDatabase, cloudStore: cloudStore)
        let deviceASourceRepository: GRDBSourceRepository = GRDBSourceRepository(database: deviceADatabase)
        let deviceBSourceRepository: GRDBSourceRepository = GRDBSourceRepository(database: deviceBDatabase)

        try deviceASourceRepository.saveSource(Self.makeRSSSource(id: "source-1", name: "Cloud Source", updatedAt: 100))
        try deviceASourceRepository.deleteSource(id: "source-1")

        _ = try deviceBService.syncSources(limit: 10)
        #expect(try deviceBSourceRepository.fetchSources().map(\.id) == ["source-1"])

        _ = try deviceAService.syncSources(limit: 10)
        _ = try deviceBService.syncSources(limit: 10)

        #expect(try deviceBSourceRepository.fetchSources().isEmpty)
    }

    private static func makeDatabase() throws -> AppDatabase {
        let path: String = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrowseCraftSourceSyncTests-\(UUID().uuidString).sqlite")
            .path
        return try AppDatabase(path: path)
    }

    private static func makeService(
        database: AppDatabase,
        cloudStore: CloudRecordStore
    ) -> SourceSyncService {
        return SourceSyncService(
            localStore: GRDBSourceSyncLocalStore(database: database),
            cloudStore: cloudStore
        )
    }

    private static func insertSource(_ source: Source, into database: AppDatabase) throws {
        try database.queue.write { database in
            var record: SourceRecord = try SourceRecord(source: source)
            try record.save(database)
        }
    }

    private static func sourceRecord(id: String, in database: AppDatabase) throws -> SourceRecord? {
        return try database.queue.read { database in
            return try SourceRecord.fetchOne(
                database,
                key: ["userID": AppUser.localDefaultID, "id": id]
            )
        }
    }

    private static func payload(
        id: String,
        name: String,
        updatedAt: TimeInterval,
        deletedAt: TimeInterval? = nil
    ) throws -> SourceCloudPayload {
        let record: SourceRecord = try SourceRecord(source: Self.makeRSSSource(id: id, name: name, updatedAt: updatedAt))
        var payload: SourceCloudPayload = SourceCloudPayload(record: record)
        payload.deletedAt = deletedAt.map(Date.init(timeIntervalSince1970:))
        return payload
    }

    private static func makeRSSSource(id: String, name: String, updatedAt: TimeInterval) -> Source {
        return Source(
            id: id,
            name: name,
            baseURL: "https://example.test",
            type: .rss,
            configuration: .rss(
                RSSSourceConfiguration(
                    definition: RSSSourceDefinition(
                        feedURL: URL(string: "https://example.test/feed.xml") ?? URL(fileURLWithPath: "/"),
                        requiresAccount: false,
                        refreshPolicy: .manual
                    )
                )
            ),
            enabled: true,
            createdAt: Date(timeIntervalSince1970: 50),
            updatedAt: Date(timeIntervalSince1970: updatedAt)
        )
    }
}
