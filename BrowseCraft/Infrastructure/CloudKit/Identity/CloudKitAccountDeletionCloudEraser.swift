import CloudKit
import Foundation

/// 中文注释：删除账号后清 iCloud（docs/design/Account-Deletion-Design.md 第六节）：归属判定通过后删 zone `BrowseCraftSync`
/// 与默认 zone 里的 `AppUserIdentity/default`。只碰本 App 容器的私有库。
actor CloudKitAccountDeletionCloudEraser: AccountDeletionCloudDataErasing {
    private let containerIdentifier: String
    private let container: CKContainer
    private let scopeDeriver: CloudAccountScopeDeriver
    private let zoneID: CKRecordZone.ID
    private let identityRecordID: CKRecord.ID

    init(
        containerIdentifier: String,
        scopeDeriver: CloudAccountScopeDeriver = CloudAccountScopeDeriver()
    ) {
        self.containerIdentifier = containerIdentifier
        self.container = CKContainer(identifier: containerIdentifier)
        self.scopeDeriver = scopeDeriver
        self.zoneID = CKRecordZone.ID(zoneName: CloudKitRecordMapper.zoneName)
        self.identityRecordID = CKRecord.ID(recordName: CloudAppUserIdentityRecordContract.recordName)
    }

    func eraseCloudData(
        for userID: UUID,
        associatedScopes: [CloudAccountScope]
    ) async throws -> AccountDeletionCloudErasure {
        do {
            guard try await self.container.accountStatus() == .available else {
                throw AccountDeletionCloudErasureError.accountUnavailable
            }
            let userRecordID: CKRecord.ID = try await self.container.userRecordID()
            let currentScope: CloudAccountScope = self.scopeDeriver.derive(
                containerIdentifier: self.containerIdentifier,
                userRecordName: userRecordID.recordName
            )
            let database: CKDatabase = self.container.privateCloudDatabase
            let identityRecord: CKRecord? = try await self.fetchIdentityRecord(in: database)
            let identityUserID: UUID? = (identityRecord?[CloudAppUserIdentityRecordContract.Field.userID] as? String)
                .flatMap(UUID.init(uuidString:))
            guard AccountDeletionCloudOwnership.isOwned(
                identityUserID: identityUserID,
                deletedUserID: userID,
                currentScope: currentScope,
                associatedScopes: associatedScopes
            ) else {
                return .notOwned
            }

            do {
                _ = try await database.modifyRecordZones(saving: [], deleting: [self.zoneID])
            } catch where CKSyncEngineCloudRecordStore.containsZoneNotFound(error) {
                // 中文注释：zone 本来就不存在（从没开过同步或已被清掉），算删成。
            }
            if identityRecord != nil, identityUserID == userID {
                do {
                    _ = try await database.modifyRecords(saving: [], deleting: [self.identityRecordID])
                } catch where Self.code(of: error) == .unknownItem {
                }
            }
            return .erased
        } catch let error as AccountDeletionCloudErasureError {
            throw error
        } catch {
            switch Self.code(of: error) {
            case .notAuthenticated, .accountTemporarilyUnavailable, .permissionFailure:
                throw AccountDeletionCloudErasureError.accountUnavailable
            default:
                throw AccountDeletionCloudErasureError.temporarilyUnavailable
            }
        }
    }

    private func fetchIdentityRecord(in database: CKDatabase) async throws -> CKRecord? {
        do {
            let results: [CKRecord.ID: Result<CKRecord, any Error>] = try await database.records(
                for: [self.identityRecordID]
            )
            switch results[self.identityRecordID] {
            case .success(let record):
                return record
            case .failure(let error) where Self.code(of: error) == .unknownItem:
                return nil
            case .failure(let error):
                throw error
            case nil:
                return nil
            }
        } catch where Self.code(of: error) == .unknownItem {
            return nil
        }
    }

    /// 中文注释：批量请求把真正的错误包在 partialFailure 里，取第一条子错误的码。
    private static func code(of error: any Error) -> CKError.Code? {
        let nsError: NSError = error as NSError
        guard nsError.domain == CKErrorDomain else {
            return nil
        }
        if nsError.code == CKError.Code.partialFailure.rawValue,
           let partialErrors: NSDictionary = nsError.userInfo[CKPartialErrorsByItemIDKey] as? NSDictionary,
           let first: NSError = partialErrors.allValues.first as? NSError,
           first.domain == CKErrorDomain {
            return CKError.Code(rawValue: first.code)
        }
        return CKError.Code(rawValue: nsError.code)
    }
}
