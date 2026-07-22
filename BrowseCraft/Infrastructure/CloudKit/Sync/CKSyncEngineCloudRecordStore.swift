import CloudKit
import Foundation

/// 中文注释：每个已确认 cloud scope 使用独立的 CKSyncEngine state，所有记录共用 BrowseCraftSync zone。
actor CKSyncEngineCloudRecordStore: CloudRecordStore, CKSyncEngineDelegate {
    private let database: CKDatabase
    private let stateStore: any CloudSyncEngineStateStoring
    private let metadataStore: any CloudRecordMetadataStoring
    private let securityValidator: any CloudSyncPayloadSecurityValidating
    private let accountScopeProvider: any ActiveAccountScopeProviding
    private let mapper: CloudKitRecordMapper

    private var syncEngine: CKSyncEngine?
    private var engineAccountScope: CloudAccountScope?
    private var latestStateSerialization: CKSyncEngine.State.Serialization?
    private var zoneReadyScopes: Set<CloudAccountScope> = []
    private var accountWasInvalidated: Bool = false

    private var fetchedSourcesByID: [String: SourceCloudPayload] = [:]
    private var fetchedFavoriteItemsByID: [String: FavoriteItemCloudPayload] = [:]
    private var sourceFetchPending: Bool = false
    private var favoriteFetchPending: Bool = false
    private var fetchedBatchHasInvalidRecord: Bool = false
    private var stagedRecordsByID: [CKRecord.ID: CKRecord] = [:]
    private var savedRecordIDs: Set<CKRecord.ID> = []
    private var failedRecordSaves: [CKRecord.ID: CloudRecordSaveFailure] = [:]

    init(
        container: CKContainer,
        stateStore: any CloudSyncEngineStateStoring,
        metadataStore: any CloudRecordMetadataStoring,
        securityValidator: any CloudSyncPayloadSecurityValidating,
        accountScopeProvider: any ActiveAccountScopeProviding
    ) {
        self.database = container.privateCloudDatabase
        self.stateStore = stateStore
        self.metadataStore = metadataStore
        self.securityValidator = securityValidator
        self.accountScopeProvider = accountScopeProvider
        self.mapper = CloudKitRecordMapper()
    }

    func fetchChangedSourceRecords(since token: Data?) async throws -> SourceCloudChangeSet {
        _ = token
        let accountScope: CloudAccountScope = try self.currentCloudScope()
        if self.sourceFetchPending == false {
            try await self.fetchChanges(for: accountScope)
            self.sourceFetchPending = true
            self.favoriteFetchPending = true
        }
        try self.requireCurrentAccount(accountScope)

        let records: [SourceCloudPayload] = self.fetchedSourcesByID.values.sorted {
            $0.sourceID < $1.sourceID
        }
        self.fetchedSourcesByID.removeAll()
        self.sourceFetchPending = false
        return SourceCloudChangeSet(records: records, changeToken: nil)
    }

    func fetchChangedFavoriteItemRecords(
        since token: Data?
    ) async throws -> FavoriteItemCloudChangeSet {
        _ = token
        let accountScope: CloudAccountScope = try self.currentCloudScope()
        if self.favoriteFetchPending == false {
            try await self.fetchChanges(for: accountScope)
            self.sourceFetchPending = true
            self.favoriteFetchPending = true
        }
        try self.requireCurrentAccount(accountScope)

        let records: [FavoriteItemCloudPayload] = self.fetchedFavoriteItemsByID.values.sorted {
            $0.itemID < $1.itemID
        }
        self.fetchedFavoriteItemsByID.removeAll()
        self.favoriteFetchPending = false
        return FavoriteItemCloudChangeSet(records: records, changeToken: nil)
    }

    func saveSourceRecords(
        _ records: [SourceCloudPayload]
    ) async throws -> CloudRecordBatchSaveResult {
        let accountScope: CloudAccountScope = try self.currentCloudScope()
        var prepared: [(entityID: String, record: CKRecord)] = []
        var failures: [CloudRecordSaveFailure] = []

        for payload: SourceCloudPayload in records {
            do {
                try self.securityValidator.validate(payload)
                let recordID: CKRecord.ID = self.mapper.recordID(forSourceID: payload.sourceID)
                let record: CKRecord = try self.makeRecord(
                    recordType: CloudKitRecordMapper.sourceRecordType,
                    recordID: recordID,
                    accountScope: accountScope
                )
                try self.mapper.apply(payload, to: record)
                prepared.append((payload.sourceID, record))
            } catch {
                failures.append(
                    CloudRecordSaveFailure(
                        entityID: payload.sourceID,
                        code: Self.safeCode(for: error),
                        retryAfter: nil
                    )
                )
            }
        }

        let result: CloudRecordBatchSaveResult = try await self.send(
            prepared,
            accountScope: accountScope
        )
        return CloudRecordBatchSaveResult(
            savedEntityIDs: result.savedEntityIDs,
            failures: failures + result.failures
        )
    }

    func saveFavoriteItemRecords(
        _ records: [FavoriteItemCloudPayload]
    ) async throws -> CloudRecordBatchSaveResult {
        let accountScope: CloudAccountScope = try self.currentCloudScope()
        var prepared: [(entityID: String, record: CKRecord)] = []
        var failures: [CloudRecordSaveFailure] = []

        for payload: FavoriteItemCloudPayload in records {
            do {
                try self.securityValidator.validate(payload)
                let recordID: CKRecord.ID = self.mapper.recordID(forFavoriteItemID: payload.itemID)
                let record: CKRecord = try self.makeRecord(
                    recordType: CloudKitRecordMapper.favoriteItemRecordType,
                    recordID: recordID,
                    accountScope: accountScope
                )
                try self.mapper.apply(payload, to: record)
                prepared.append((payload.itemID, record))
            } catch {
                failures.append(
                    CloudRecordSaveFailure(
                        entityID: payload.itemID,
                        code: Self.safeCode(for: error),
                        retryAfter: nil
                    )
                )
            }
        }

        let result: CloudRecordBatchSaveResult = try await self.send(
            prepared,
            accountScope: accountScope
        )
        return CloudRecordBatchSaveResult(
            savedEntityIDs: result.savedEntityIDs,
            failures: failures + result.failures
        )
    }

    func commitState(for accountScope: CloudAccountScope) async throws {
        try self.requireCurrentAccount(accountScope)
        guard self.engineAccountScope == accountScope,
              let serialization: CKSyncEngine.State.Serialization = self.latestStateSerialization else {
            return
        }
        let data: Data = try JSONEncoder().encode(serialization)
        try self.stateStore.saveState(data, for: accountScope)
    }

    func cancelOperations() async {
        await self.syncEngine?.cancelOperations()
        self.syncEngine = nil
        self.engineAccountScope = nil
        self.latestStateSerialization = nil
        self.stagedRecordsByID.removeAll()
        self.savedRecordIDs.removeAll()
        self.failedRecordSaves.removeAll()
        self.fetchedSourcesByID.removeAll()
        self.fetchedFavoriteItemsByID.removeAll()
        self.sourceFetchPending = false
        self.favoriteFetchPending = false
        self.fetchedBatchHasInvalidRecord = false
        self.accountWasInvalidated = false
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            self.latestStateSerialization = update.stateSerialization

        case .accountChange(let change):
            switch change.changeType {
            case .signIn:
                break
            case .signOut, .switchAccounts:
                self.accountWasInvalidated = true
            @unknown default:
                self.accountWasInvalidated = true
            }

        case .fetchedRecordZoneChanges(let changes):
            await self.handleFetchedRecordZoneChanges(changes)

        case .sentRecordZoneChanges(let changes):
            await self.handleSentRecordZoneChanges(changes)

        case .didFetchRecordZoneChanges(let event):
            if event.zoneID == self.mapper.zoneID,
               event.error?.code == .changeTokenExpired {
                self.latestStateSerialization = nil
            }

        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pendingChanges: [CKSyncEngine.PendingRecordZoneChange] = syncEngine.state
            .pendingRecordZoneChanges
            .filter { context.options.scope.contains($0) }
        var recordsToSave: [CKRecord] = []

        for change: CKSyncEngine.PendingRecordZoneChange in pendingChanges {
            guard case .saveRecord(let recordID) = change,
                  let record: CKRecord = self.stagedRecordsByID[recordID] else {
                continue
            }
            recordsToSave.append(record)
        }
        guard recordsToSave.isEmpty == false else {
            return nil
        }
        return CKSyncEngine.RecordZoneChangeBatch(
            recordsToSave: recordsToSave,
            recordIDsToDelete: [],
            atomicByZone: false
        )
    }

    private func fetchChanges(for accountScope: CloudAccountScope) async throws {
        let engine: CKSyncEngine = try await self.engine(for: accountScope)
        self.fetchedBatchHasInvalidRecord = false
        let options: CKSyncEngine.FetchChangesOptions = CKSyncEngine.FetchChangesOptions(
            scope: .zoneIDs([self.mapper.zoneID])
        )
        do {
            try await engine.fetchChanges(options)
        } catch let error as CKError where error.code == .changeTokenExpired {
            try self.stateStore.clearState(for: accountScope)
            await engine.cancelOperations()
            self.syncEngine = nil
            self.engineAccountScope = nil
            self.latestStateSerialization = nil
            let resetEngine: CKSyncEngine = try await self.engine(for: accountScope)
            try await resetEngine.fetchChanges(options)
        }
        if self.fetchedBatchHasInvalidRecord {
            await self.cancelOperations()
            throw CKSyncEngineCloudRecordStoreError.invalidFetchedRecord
        }
        try self.requireCurrentAccount(accountScope)
    }

    private func send(
        _ prepared: [(entityID: String, record: CKRecord)],
        accountScope: CloudAccountScope
    ) async throws -> CloudRecordBatchSaveResult {
        guard prepared.isEmpty == false else {
            return CloudRecordBatchSaveResult(savedEntityIDs: [], failures: [])
        }
        let engine: CKSyncEngine = try await self.engine(for: accountScope)
        let recordIDs: [CKRecord.ID] = prepared.map { $0.record.recordID }
        let entityIDByRecordID: [CKRecord.ID: String] = Dictionary(
            uniqueKeysWithValues: prepared.map { ($0.record.recordID, $0.entityID) }
        )

        for item: (entityID: String, record: CKRecord) in prepared {
            self.stagedRecordsByID[item.record.recordID] = item.record
            self.savedRecordIDs.remove(item.record.recordID)
            self.failedRecordSaves.removeValue(forKey: item.record.recordID)
        }
        engine.state.add(
            pendingRecordZoneChanges: recordIDs.map { .saveRecord($0) }
        )

        let options: CKSyncEngine.SendChangesOptions = CKSyncEngine.SendChangesOptions(
            scope: .recordIDs(recordIDs)
        )
        try await engine.sendChanges(options)
        try self.requireCurrentAccount(accountScope)

        var savedEntityIDs: Set<String> = []
        var failures: [CloudRecordSaveFailure] = []
        for recordID: CKRecord.ID in recordIDs {
            guard let entityID: String = entityIDByRecordID[recordID] else {
                continue
            }
            if self.savedRecordIDs.contains(recordID) {
                savedEntityIDs.insert(entityID)
                self.stagedRecordsByID.removeValue(forKey: recordID)
            } else if var failure: CloudRecordSaveFailure = self.failedRecordSaves[recordID] {
                failure.entityID = entityID
                failures.append(failure)
            } else {
                failures.append(
                    CloudRecordSaveFailure(
                        entityID: entityID,
                        code: "noServerResult",
                        retryAfter: nil
                    )
                )
            }
            self.savedRecordIDs.remove(recordID)
            self.failedRecordSaves.removeValue(forKey: recordID)
        }
        return CloudRecordBatchSaveResult(
            savedEntityIDs: savedEntityIDs,
            failures: failures
        )
    }

    private func engine(for accountScope: CloudAccountScope) async throws -> CKSyncEngine {
        try self.requireCurrentAccount(accountScope)
        if self.engineAccountScope == accountScope,
           let syncEngine: CKSyncEngine = self.syncEngine {
            try await self.ensureZone(for: accountScope)
            return syncEngine
        }

        await self.syncEngine?.cancelOperations()
        let stateData: Data? = try self.stateStore.loadState(for: accountScope)
        let serialization: CKSyncEngine.State.Serialization? = try stateData.map {
            try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0)
        }
        var configuration: CKSyncEngine.Configuration = CKSyncEngine.Configuration(
            database: self.database,
            stateSerialization: serialization,
            delegate: self
        )
        configuration.automaticallySync = true
        configuration.subscriptionID = "BrowseCraftSync"

        let syncEngine: CKSyncEngine = CKSyncEngine(configuration)
        self.syncEngine = syncEngine
        self.engineAccountScope = accountScope
        self.latestStateSerialization = serialization
        self.accountWasInvalidated = false
        self.fetchedSourcesByID.removeAll()
        self.fetchedFavoriteItemsByID.removeAll()
        self.sourceFetchPending = false
        self.favoriteFetchPending = false
        try await self.ensureZone(for: accountScope)
        return syncEngine
    }

    private func ensureZone(for accountScope: CloudAccountScope) async throws {
        guard self.zoneReadyScopes.contains(accountScope) == false else {
            return
        }
        let zone: CKRecordZone = CKRecordZone(zoneID: self.mapper.zoneID)
        let result = try await self.database.modifyRecordZones(
            saving: [zone],
            deleting: []
        )
        if let saveResult = result.saveResults[self.mapper.zoneID] {
            _ = try saveResult.get()
        }
        self.zoneReadyScopes.insert(accountScope)
    }

    private func handleFetchedRecordZoneChanges(
        _ changes: CKSyncEngine.Event.FetchedRecordZoneChanges
    ) async {
        guard let accountScope: CloudAccountScope = self.engineAccountScope else {
            return
        }
        for modification: CKDatabase.RecordZoneChange.Modification in changes.modifications {
            let record: CKRecord = modification.record
            guard record.recordID.zoneID == self.mapper.zoneID else {
                continue
            }
            do {
                try self.saveSystemFields(of: record, accountScope: accountScope)
                switch record.recordType {
                case CloudKitRecordMapper.sourceRecordType:
                    let payload: SourceCloudPayload = try self.mapper.sourcePayload(from: record)
                    self.fetchedSourcesByID[payload.sourceID] = payload
                case CloudKitRecordMapper.favoriteItemRecordType:
                    let payload: FavoriteItemCloudPayload = try self.mapper.favoriteItemPayload(from: record)
                    self.fetchedFavoriteItemsByID[payload.itemID] = payload
                default:
                    continue
                }
            } catch {
                self.fetchedBatchHasInvalidRecord = true
            }
        }
    }

    private func handleSentRecordZoneChanges(
        _ changes: CKSyncEngine.Event.SentRecordZoneChanges
    ) async {
        guard let accountScope: CloudAccountScope = self.engineAccountScope else {
            return
        }
        for record: CKRecord in changes.savedRecords {
            self.savedRecordIDs.insert(record.recordID)
            try? self.saveSystemFields(of: record, accountScope: accountScope)
        }
        for failedSave: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave in changes.failedRecordSaves {
            var failureCode: String = "ck_\(failedSave.error.code.rawValue)"
            if let serverRecord: CKRecord = failedSave.error.serverRecord {
                do {
                    try self.bufferServerRecordForConflictResolution(serverRecord)
                    try self.saveSystemFields(of: serverRecord, accountScope: accountScope)
                } catch {
                    failureCode = "mapping_invalidServerRecord"
                }
            }
            if failedSave.error.code == .serverRecordChanged {
                self.stagedRecordsByID.removeValue(forKey: failedSave.record.recordID)
            }
            self.failedRecordSaves[failedSave.record.recordID] = CloudRecordSaveFailure(
                entityID: "",
                code: failureCode,
                retryAfter: failedSave.error.retryAfterSeconds
            )
        }
    }

    /// 中文注释：change-tag 冲突的服务端版本必须进入下一轮业务合并，不能只更新 system fields 后盲目覆盖。
    private func bufferServerRecordForConflictResolution(_ record: CKRecord) throws {
        switch record.recordType {
        case CloudKitRecordMapper.sourceRecordType:
            let payload: SourceCloudPayload = try self.mapper.sourcePayload(from: record)
            self.fetchedSourcesByID[payload.sourceID] = payload
        case CloudKitRecordMapper.favoriteItemRecordType:
            let payload: FavoriteItemCloudPayload = try self.mapper.favoriteItemPayload(from: record)
            self.fetchedFavoriteItemsByID[payload.itemID] = payload
        default:
            throw CloudKitRecordMappingError.unexpectedRecordType
        }
    }

    private func makeRecord(
        recordType: CKRecord.RecordType,
        recordID: CKRecord.ID,
        accountScope: CloudAccountScope
    ) throws -> CKRecord {
        guard let systemFields: Data = try self.metadataStore.systemFields(
            accountScope: accountScope,
            recordName: recordID.recordName
        ) else {
            return CKRecord(recordType: recordType, recordID: recordID)
        }
        let unarchiver: NSKeyedUnarchiver = try NSKeyedUnarchiver(forReadingFrom: systemFields)
        unarchiver.requiresSecureCoding = true
        defer { unarchiver.finishDecoding() }
        guard let record: CKRecord = CKRecord(coder: unarchiver),
              record.recordID == recordID,
              record.recordType == recordType else {
            throw CKSyncEngineCloudRecordStoreError.invalidSystemFields
        }
        return record
    }

    private func saveSystemFields(
        of record: CKRecord,
        accountScope: CloudAccountScope
    ) throws {
        let archiver: NSKeyedArchiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        try self.metadataStore.saveSystemFields(
            archiver.encodedData,
            accountScope: accountScope,
            recordName: record.recordID.recordName
        )
    }

    private func currentCloudScope() throws -> CloudAccountScope {
        let accountScope: CloudAccountScope = self.accountScopeProvider.currentScope
        guard accountScope.isCloud else {
            throw CloudSyncSessionError.synchronizationDisabled
        }
        return accountScope
    }

    private func requireCurrentAccount(_ accountScope: CloudAccountScope) throws {
        guard self.accountWasInvalidated == false,
              self.accountScopeProvider.currentScope == accountScope else {
            throw CloudSyncSessionError.accountChanged
        }
    }

    private static func safeCode(for error: any Error) -> String {
        if let securityError: CloudSyncPayloadSecurityError = error as? CloudSyncPayloadSecurityError {
            return "security_\(securityError.issue.rawValue)"
        }
        if let mappingError: CloudKitRecordMappingError = error as? CloudKitRecordMappingError {
            switch mappingError {
            case .unexpectedRecordType:
                return "mapping_unexpectedRecordType"
            case .recordIDMismatch:
                return "mapping_recordIDMismatch"
            case .missingField:
                return "mapping_missingField"
            }
        }
        return "local_\(String(reflecting: type(of: error)))"
    }
}

private enum CKSyncEngineCloudRecordStoreError: Error {
    case invalidSystemFields
    case invalidFetchedRecord
}
