import CloudKit
import Foundation
import Testing
@testable import BrowseCraft

struct CloudKitAppUserIdentityStoreTests {
    @Test func mapperUsesPrivateDatabaseDefaultZoneContract() throws {
        let mapper: CloudKitAppUserIdentityRecordMapper =
            CloudKitAppUserIdentityRecordMapper()
        let identity: CloudAppUserIdentity = .proposed(
            userID: UUID(),
            at: Date(timeIntervalSince1970: 1)
        )

        let record: CKRecord = try mapper.record(from: identity)

        #expect(record.recordType == "AppUserIdentity")
        #expect(record.recordID.recordName == "default")
        #expect(record.recordID.zoneID == CKRecordZone.default().zoneID)
        #expect(record["userID"] as? String == identity.userID.uuidString)
        #expect((record["schemaVersion"] as? NSNumber)?.intValue == 1)
        #expect(record["createdAt"] as? Date == identity.createdAt)
        #expect(record["updatedAt"] as? Date == identity.updatedAt)
    }

    @Test func mapperRejectsMalformedIdentityRecord() throws {
        let mapper: CloudKitAppUserIdentityRecordMapper =
            CloudKitAppUserIdentityRecordMapper()
        let record: CKRecord = CKRecord(
            recordType: CloudAppUserIdentityRecordContract.recordType,
            recordID: mapper.recordID
        )
        record["schemaVersion"] = NSNumber(value: 1)
        record["userID"] = "not-a-uuid" as CKRecordValue
        record["createdAt"] = Date(timeIntervalSince1970: 1) as CKRecordValue
        record["updatedAt"] = Date(timeIntervalSince1970: 1) as CKRecordValue

        #expect(
            throws: CloudKitAppUserIdentityRecordMappingError.missingOrInvalidField(
                "userID"
            )
        ) {
            _ = try mapper.identity(from: record)
        }
    }

    @Test func mapperRejectsUnsupportedSchema() throws {
        let mapper: CloudKitAppUserIdentityRecordMapper =
            CloudKitAppUserIdentityRecordMapper()
        let record: CKRecord = CKRecord(
            recordType: CloudAppUserIdentityRecordContract.recordType,
            recordID: mapper.recordID
        )
        record["schemaVersion"] = NSNumber(value: 2)
        record["userID"] = UUID().uuidString as CKRecordValue
        record["createdAt"] = Date(timeIntervalSince1970: 1) as CKRecordValue
        record["updatedAt"] = Date(timeIntervalSince1970: 1) as CKRecordValue

        #expect(
            throws: CloudKitAppUserIdentityRecordMappingError.unsupportedSchemaVersion(2)
        ) {
            _ = try mapper.identity(from: record)
        }
    }

    @Test func concurrentCreateReturnsExistingCloudIdentityWithoutOverwrite() async throws {
        let mapper: CloudKitAppUserIdentityRecordMapper =
            CloudKitAppUserIdentityRecordMapper()
        let existingIdentity: CloudAppUserIdentity = .proposed(
            userID: UUID(),
            at: Date(timeIntervalSince1970: 1)
        )
        let existingRecord: CKRecord = try mapper.record(from: existingIdentity)
        let database: ConflictingCloudAppUserIdentityDatabase =
            ConflictingCloudAppUserIdentityDatabase(existingRecord: existingRecord)
        let store: CloudKitAppUserIdentityStore =
            CloudKitAppUserIdentityStore(database: database)

        let returnedIdentity: CloudAppUserIdentity = try await store.createIdentityIfAbsent(
            .proposed(
                userID: UUID(),
                at: Date(timeIntervalSince1970: 2)
            )
        )

        #expect(returnedIdentity == existingIdentity)
        let createAttemptCount: Int = await database.createAttemptCount
        #expect(createAttemptCount == 1)
    }
}

private actor ConflictingCloudAppUserIdentityDatabase: CloudAppUserIdentityDatabase {
    private let existingRecord: CKRecord
    private(set) var createAttemptCount: Int = 0

    init(existingRecord: CKRecord) {
        self.existingRecord = existingRecord
    }

    func fetchRecord(withID recordID: CKRecord.ID) async throws -> CKRecord? {
        return self.existingRecord.recordID == recordID ? self.existingRecord : nil
    }

    func createRecord(_ record: CKRecord) async throws -> CKRecord {
        self.createAttemptCount += 1
        throw NSError(
            domain: CKErrorDomain,
            code: CKError.Code.serverRecordChanged.rawValue
        )
    }
}
