import CloudKit
import Foundation

/// 中文注释：窄化 CKDatabase，确保 Identity Store 可以在不访问真实 iCloud 的情况下验证。
protocol CloudAppUserIdentityDatabase: Sendable {
    func fetchRecord(withID recordID: CKRecord.ID) async throws -> CKRecord?
    func createRecord(_ record: CKRecord) async throws -> CKRecord
}

/// 中文注释：只操作传入 CKContainer 的 Private Database；不创建或访问自定义 zone。
actor CKPrivateAppUserIdentityDatabase: CloudAppUserIdentityDatabase {
    private let database: CKDatabase

    init(container: CKContainer) {
        self.database = container.privateCloudDatabase
    }

    func fetchRecord(withID recordID: CKRecord.ID) async throws -> CKRecord? {
        do {
            let results: [CKRecord.ID: Result<CKRecord, any Error>] = try await self.database.records(
                for: [recordID]
            )
            guard let result: Result<CKRecord, any Error> = results[recordID] else {
                throw CloudKitAppUserIdentityDatabaseError.missingRecordResult
            }
            switch result {
            case .success(let record):
                return record
            case .failure(let error):
                guard Self.cloudErrorCode(for: error) == .unknownItem else {
                    throw error
                }
                return nil
            }
        } catch {
            let recordError: any Error = Self.recordError(
                from: error,
                recordID: recordID
            )
            guard Self.cloudErrorCode(for: recordError) == .unknownItem else {
                throw recordError
            }
            return nil
        }
    }

    func createRecord(_ record: CKRecord) async throws -> CKRecord {
        do {
            let result = try await self.database.modifyRecords(
                saving: [record],
                deleting: [],
                savePolicy: .ifServerRecordUnchanged,
                atomically: false
            )
            guard let saveResult: Result<CKRecord, any Error> =
                result.saveResults[record.recordID] else {
                throw CloudKitAppUserIdentityDatabaseError.missingRecordResult
            }
            return try saveResult.get()
        } catch {
            throw Self.recordError(from: error, recordID: record.recordID)
        }
    }

    private static func cloudErrorCode(for error: any Error) -> CKError.Code? {
        let nsError: NSError = error as NSError
        guard nsError.domain == CKErrorDomain else {
            return nil
        }
        return CKError.Code(rawValue: nsError.code)
    }

    private static func recordError(
        from error: any Error,
        recordID: CKRecord.ID
    ) -> any Error {
        let nsError: NSError = error as NSError
        guard nsError.domain == CKErrorDomain,
              nsError.code == CKError.Code.partialFailure.rawValue,
              let partialErrors: [AnyHashable: any Error] =
                nsError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: any Error],
              let recordError: any Error = partialErrors[recordID] else {
            return error
        }
        return recordError
    }
}

/// 中文注释：AppUserIdentity/default 位于 Private Database default zone，与 BrowseCraftSync 分离。
actor CloudKitAppUserIdentityStore: CloudAppUserIdentityStoring {
    private let database: any CloudAppUserIdentityDatabase
    private let mapper: CloudKitAppUserIdentityRecordMapper

    init(container: CKContainer) {
        self.database = CKPrivateAppUserIdentityDatabase(container: container)
        self.mapper = CloudKitAppUserIdentityRecordMapper()
    }

    init(database: any CloudAppUserIdentityDatabase) {
        self.database = database
        self.mapper = CloudKitAppUserIdentityRecordMapper()
    }

    func fetchIdentity() async throws -> CloudAppUserIdentity? {
        do {
            guard let record: CKRecord = try await self.database.fetchRecord(
                withID: self.mapper.recordID
            ) else {
                return nil
            }
            return try self.mapper.identity(from: record)
        } catch {
            throw Self.storeError(for: error)
        }
    }

    func createIdentityIfAbsent(
        _ proposedIdentity: CloudAppUserIdentity
    ) async throws -> CloudAppUserIdentity {
        guard proposedIdentity.usesSupportedSchema else {
            throw CloudAppUserIdentityStoreError.unsupportedSchemaVersion(
                proposedIdentity.schemaVersion
            )
        }

        do {
            let proposedRecord: CKRecord = try self.mapper.record(from: proposedIdentity)
            let savedRecord: CKRecord = try await self.database.createRecord(proposedRecord)
            return try self.mapper.identity(from: savedRecord)
        } catch {
            guard Self.shouldResolveCreateFromServer(error) else {
                throw Self.storeError(for: error)
            }

            do {
                if let serverRecord: CKRecord = (error as? CKError)?.serverRecord {
                    return try self.mapper.identity(from: serverRecord)
                }
                guard let serverRecord: CKRecord = try await self.database.fetchRecord(
                    withID: self.mapper.recordID
                ) else {
                    throw CloudAppUserIdentityStoreError.temporarilyUnavailable
                }
                return try self.mapper.identity(from: serverRecord)
            } catch {
                throw Self.storeError(for: error)
            }
        }
    }

    private static func shouldResolveCreateFromServer(_ error: any Error) -> Bool {
        switch Self.cloudErrorCode(for: error) {
        case .serverRecordChanged, .serverResponseLost:
            return true
        default:
            return false
        }
    }

    private static func storeError(for error: any Error) -> CloudAppUserIdentityStoreError {
        if let storeError: CloudAppUserIdentityStoreError =
            error as? CloudAppUserIdentityStoreError {
            return storeError
        }
        if let mappingError: CloudKitAppUserIdentityRecordMappingError =
            error as? CloudKitAppUserIdentityRecordMappingError {
            switch mappingError {
            case .unsupportedSchemaVersion(let version):
                return .unsupportedSchemaVersion(version)
            case .unexpectedRecordType,
                 .recordIDMismatch,
                 .missingOrInvalidField,
                 .invalidTimestampOrder:
                return .malformedRecord
            }
        }

        switch Self.cloudErrorCode(for: error) {
        case .notAuthenticated, .accountTemporarilyUnavailable:
            return .accountUnavailable
        case .permissionFailure:
            return .accessDenied
        case .networkUnavailable,
             .networkFailure,
             .serviceUnavailable,
             .requestRateLimited,
             .zoneBusy,
             .serverResponseLost:
            return .temporarilyUnavailable
        default:
            return .operationFailed
        }
    }

    private static func cloudErrorCode(for error: any Error) -> CKError.Code? {
        let nsError: NSError = error as NSError
        guard nsError.domain == CKErrorDomain else {
            return nil
        }
        return CKError.Code(rawValue: nsError.code)
    }
}

struct CloudKitAppUserIdentityRecordMapper: Sendable {
    let recordID: CKRecord.ID

    init() {
        self.recordID = CKRecord.ID(
            recordName: CloudAppUserIdentityRecordContract.recordName
        )
    }

    func record(from identity: CloudAppUserIdentity) throws -> CKRecord {
        guard identity.usesSupportedSchema else {
            throw CloudKitAppUserIdentityRecordMappingError.unsupportedSchemaVersion(
                identity.schemaVersion
            )
        }
        guard identity.createdAt <= identity.updatedAt else {
            throw CloudKitAppUserIdentityRecordMappingError.invalidTimestampOrder
        }

        let record: CKRecord = CKRecord(
            recordType: CloudAppUserIdentityRecordContract.recordType,
            recordID: self.recordID
        )
        record[CloudAppUserIdentityRecordContract.Field.userID] =
            identity.userID.uuidString as CKRecordValue
        record[CloudAppUserIdentityRecordContract.Field.schemaVersion] =
            NSNumber(value: identity.schemaVersion)
        record[CloudAppUserIdentityRecordContract.Field.createdAt] =
            identity.createdAt as CKRecordValue
        record[CloudAppUserIdentityRecordContract.Field.updatedAt] =
            identity.updatedAt as CKRecordValue
        return record
    }

    func identity(from record: CKRecord) throws -> CloudAppUserIdentity {
        guard record.recordType == CloudAppUserIdentityRecordContract.recordType else {
            throw CloudKitAppUserIdentityRecordMappingError.unexpectedRecordType
        }
        guard record.recordID == self.recordID else {
            throw CloudKitAppUserIdentityRecordMappingError.recordIDMismatch
        }

        let schemaVersion: Int = try self.requiredInt(
            record,
            key: CloudAppUserIdentityRecordContract.Field.schemaVersion
        )
        guard schemaVersion == CloudAppUserIdentity.currentSchemaVersion else {
            throw CloudKitAppUserIdentityRecordMappingError.unsupportedSchemaVersion(
                schemaVersion
            )
        }

        let userIDString: String = try self.required(
            record,
            key: CloudAppUserIdentityRecordContract.Field.userID
        )
        guard let userID: UUID = UUID(uuidString: userIDString) else {
            throw CloudKitAppUserIdentityRecordMappingError.missingOrInvalidField(
                CloudAppUserIdentityRecordContract.Field.userID
            )
        }
        let createdAt: Date = try self.required(
            record,
            key: CloudAppUserIdentityRecordContract.Field.createdAt
        )
        let updatedAt: Date = try self.required(
            record,
            key: CloudAppUserIdentityRecordContract.Field.updatedAt
        )
        guard createdAt <= updatedAt else {
            throw CloudKitAppUserIdentityRecordMappingError.invalidTimestampOrder
        }

        return CloudAppUserIdentity(
            userID: userID,
            schemaVersion: schemaVersion,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func required<T>(_ record: CKRecord, key: String) throws -> T {
        guard let value: T = record[key] as? T else {
            throw CloudKitAppUserIdentityRecordMappingError.missingOrInvalidField(key)
        }
        return value
    }

    private func requiredInt(_ record: CKRecord, key: String) throws -> Int {
        guard let value: NSNumber = record[key] as? NSNumber else {
            throw CloudKitAppUserIdentityRecordMappingError.missingOrInvalidField(key)
        }
        return value.intValue
    }
}

enum CloudKitAppUserIdentityRecordMappingError: Error, Equatable, Sendable {
    case unexpectedRecordType
    case recordIDMismatch
    case missingOrInvalidField(String)
    case unsupportedSchemaVersion(Int)
    case invalidTimestampOrder
}

private enum CloudKitAppUserIdentityDatabaseError: Error {
    case missingRecordResult
}
