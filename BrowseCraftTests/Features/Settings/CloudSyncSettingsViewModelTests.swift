import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft

@MainActor
struct CloudSyncSettingsViewModelTests {
    @Test func enablingWithLocalDataWaitsForAFirstEnableDecision() async throws {
        let context: TestContext = try Self.makeContext()
        try context.sourceRepository.saveSource(Self.makeSource())
        await context.accountSession.start()
        let viewModel: CloudSyncSettingsViewModel = context.makeViewModel()
        await viewModel.start()

        await viewModel.setCloudSyncEnabled(true)

        let sessionSnapshot: CloudAccountSessionSnapshot = await context.accountSession.snapshot()
        #expect(viewModel.firstEnableRequest?.localDataSummary.sourceCount == 1)
        #expect(viewModel.isCloudSyncEnabled == false)
        #expect(sessionSnapshot.isSynchronizationEnabled == false)
        #expect(try context.partitionStore.preparation(for: context.cloudScope) == nil)
    }

    @Test func confirmingMergePreparesTheScopeBeforeEnablingSync() async throws {
        let context: TestContext = try Self.makeContext()
        try context.sourceRepository.saveSource(Self.makeSource())
        await context.accountSession.start()
        let viewModel: CloudSyncSettingsViewModel = context.makeViewModel()
        await viewModel.start()
        await viewModel.setCloudSyncEnabled(true)

        await viewModel.confirmFirstEnable(decision: .mergeLocalData)

        let sessionSnapshot: CloudAccountSessionSnapshot = await context.accountSession.snapshot()
        #expect(viewModel.firstEnableRequest == nil)
        #expect(viewModel.preparation?.decision == .mergeLocalData)
        #expect(viewModel.isCloudSyncEnabled)
        #expect(sessionSnapshot.isSynchronizationEnabled)
        context.activeScope.update(context.cloudScope)
        #expect(try context.sourceRepository.fetchSources().map(\.id) == ["source-1"])
    }

    @Test func enablingWithoutLocalDataPreparesCloudOnlyWithoutPrompting() async throws {
        let context: TestContext = try Self.makeContext()
        await context.accountSession.start()
        let viewModel: CloudSyncSettingsViewModel = context.makeViewModel()
        await viewModel.start()

        await viewModel.setCloudSyncEnabled(true)

        #expect(viewModel.firstEnableRequest == nil)
        #expect(viewModel.preparation?.decision == .useCloudDataOnly)
        #expect(viewModel.isCloudSyncEnabled)
        #expect(viewModel.initialRestoreState == .waitingForCloud)
    }

    @Test func successfulInitialSyncPersistsRestoreCompletionAndPublishesContentRevision() async throws {
        let context: TestContext = try Self.makeContext()
        await context.accountSession.start()
        let viewModel: CloudSyncSettingsViewModel = context.makeViewModel()
        await viewModel.start()
        await viewModel.setCloudSyncEnabled(true)
        let revisionBeforeSync: UInt64 = viewModel.contentRevision

        await viewModel.synchronizeNow()

        #expect(viewModel.initialRestoreState == .restored)
        #expect(viewModel.contentRevision > revisionBeforeSync)
        #expect(
            try context.partitionStore.preparation(for: context.cloudScope)?
                .initialSyncCompletedAt != nil
        )
    }

    @Test func cancelingFirstEnableLeavesSyncDisabledAndDoesNotPrepareTheCloudScope() async throws {
        let context: TestContext = try Self.makeContext()
        try context.sourceRepository.saveSource(Self.makeSource())
        await context.accountSession.start()
        let viewModel: CloudSyncSettingsViewModel = context.makeViewModel()
        await viewModel.start()
        await viewModel.setCloudSyncEnabled(true)

        viewModel.cancelFirstEnable()

        #expect(viewModel.firstEnableRequest == nil)
        #expect(viewModel.isCloudSyncEnabled == false)
        #expect(viewModel.initialRestoreState == .notRequired)
        #expect(try context.partitionStore.preparation(for: context.cloudScope) == nil)
    }

    @Test func choosingCloudOnlyRetainsLocalDefaultDataWithoutCopyingIt() async throws {
        let context: TestContext = try Self.makeContext()
        try context.sourceRepository.saveSource(Self.makeSource())
        await context.accountSession.start()
        let viewModel: CloudSyncSettingsViewModel = context.makeViewModel()
        await viewModel.start()
        await viewModel.setCloudSyncEnabled(true)

        await viewModel.confirmFirstEnable(decision: .useCloudDataOnly)

        #expect(try context.sourceRepository.fetchSources().isEmpty)
        context.activeScope.update(.localDefault)
        #expect(try context.sourceRepository.fetchSources().map(\.id) == ["source-1"])
        #expect(viewModel.preparation?.decision == .useCloudDataOnly)
        #expect(viewModel.isCloudSyncEnabled)
    }

    @Test func unavailableAccountCannotEnableOrStartSynchronization() async throws {
        let context: TestContext = try Self.makeContext()
        await context.accountSession.start()
        let viewModel: CloudSyncSettingsViewModel = context.makeViewModel()
        await viewModel.start()
        await context.stateProvider.setState(
            CloudAccountState(availability: .noAccount, scope: .localDefault)
        )

        await viewModel.refreshAccount()
        await viewModel.setCloudSyncEnabled(true)

        #expect(viewModel.accountAvailability == .noAccount)
        #expect(viewModel.canChangeCloudSyncEnabled == false)
        #expect(viewModel.canSynchronizeNow == false)
        #expect(viewModel.isCloudSyncEnabled == false)
        #expect(viewModel.initialRestoreState == .notRequired)
        #expect(viewModel.actionErrorMessage != nil)
    }

    @Test func temporaryAccountOutagePausesSyncButRetainsPreferenceAndPreparation() async throws {
        let context: TestContext = try Self.makeContext()
        await context.accountSession.start()
        let viewModel: CloudSyncSettingsViewModel = context.makeViewModel()
        await viewModel.start()
        await viewModel.setCloudSyncEnabled(true)
        await context.stateProvider.setState(
            CloudAccountState(
                availability: .temporarilyUnavailable,
                scope: context.cloudScope
            )
        )

        await viewModel.refreshAccount()

        #expect(viewModel.accountAvailability == .temporarilyUnavailable)
        #expect(viewModel.isCloudSyncEnabled)
        #expect(viewModel.canChangeCloudSyncEnabled == false)
        #expect(viewModel.canSynchronizeNow == false)
        #expect(viewModel.initialRestoreState == .waitingForCloud)
        #expect(try context.partitionStore.preparation(for: context.cloudScope) != nil)
    }

    @Test func disablingSyncRetainsPreparationAndPendingUploads() async throws {
        let context: TestContext = try Self.makeContext()
        await context.accountSession.start()
        let viewModel: CloudSyncSettingsViewModel = context.makeViewModel()
        await viewModel.start()
        await viewModel.setCloudSyncEnabled(true)
        try context.sourceRepository.saveSource(Self.makeSource())
        let pendingBeforeDisable: [SourceSyncPendingUpload] = try context.sourceSyncLocalStore
            .pendingUploads(accountScope: context.cloudScope)

        await viewModel.setCloudSyncEnabled(false)

        let pendingAfterDisable: [SourceSyncPendingUpload] = try context.sourceSyncLocalStore
            .pendingUploads(accountScope: context.cloudScope)
        #expect(pendingBeforeDisable.count == 1)
        #expect(pendingAfterDisable.map(\.queueItem.entityID) == ["source-1"])
        #expect(try context.partitionStore.preparation(for: context.cloudScope) != nil)
        #expect(viewModel.isCloudSyncEnabled == false)
        #expect(viewModel.initialRestoreState == .notRequired)
    }

    @Test func failedInitialRestoreCanRetryAndBecomeRestored() async throws {
        let context: TestContext = try Self.makeContext()
        await context.accountSession.start()
        let viewModel: CloudSyncSettingsViewModel = context.makeViewModel()
        await viewModel.start()
        await viewModel.setCloudSyncEnabled(true)
        context.cloudStore.failNextFetch = true

        await viewModel.synchronizeNow()

        guard case .failed(let message) = viewModel.initialRestoreState else {
            Issue.record("Expected the initial restore to expose its failure state")
            return
        }
        #expect(message.isEmpty == false)
        #expect(viewModel.errorMessage != nil)
        #expect(
            try context.partitionStore.preparation(for: context.cloudScope)?
                .initialSyncCompletedAt == nil
        )

        await viewModel.retrySynchronization()

        #expect(viewModel.initialRestoreState == .restored)
        #expect(viewModel.errorMessage == nil)
        #expect(
            try context.partitionStore.preparation(for: context.cloudScope)?
                .initialSyncCompletedAt != nil
        )
    }

    @Test func uploadFailureAfterDownloadStillCompletesInitialRestore() async throws {
        let context: TestContext = try Self.makeContext()
        await context.accountSession.start()
        let viewModel: CloudSyncSettingsViewModel = context.makeViewModel()
        await viewModel.start()
        await viewModel.setCloudSyncEnabled(true)
        try context.sourceRepository.saveSource(Self.makeSource())
        context.cloudStore.failNextSave = true

        await viewModel.synchronizeNow()

        #expect(viewModel.initialRestoreState == .restored)
        #expect(viewModel.errorMessage != nil)
        #expect(
            try context.partitionStore.preparation(for: context.cloudScope)?
                .initialSyncCompletedAt != nil
        )
        #expect(
            try context.sourceSyncLocalStore.pendingUploads(accountScope: context.cloudScope)
                .map(\.queueItem.entityID) == ["source-1"]
        )
    }

    @Test func previousAccountResultAndErrorAreHiddenAfterAccountSwitch() async throws {
        let context: TestContext = try Self.makeContext()
        let accountB: CloudAccountScope = .cloud(hash: "account-b")
        await context.accountSession.start()
        let viewModel: CloudSyncSettingsViewModel = context.makeViewModel()
        await viewModel.start()
        await viewModel.setCloudSyncEnabled(true)
        await viewModel.synchronizeNow()
        context.cloudStore.failNextFetch = true
        await viewModel.synchronizeNow()
        #expect(viewModel.lastResult?.accountScope == context.cloudScope)
        #expect(viewModel.errorMessage != nil)
        _ = try context.partitionStore.prepareCloudScope(
            accountB,
            decision: .useCloudDataOnly
        )
        context.preferences.setCloudSyncEnabled(true, for: accountB)
        await context.stateProvider.setState(
            CloudAccountState(availability: .available, scope: accountB)
        )

        await viewModel.refreshAccount()

        #expect(viewModel.accountSnapshot.state.scope == accountB)
        #expect(viewModel.lastResult == nil)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.initialRestoreState == .waitingForCloud)
    }

    @Test func restoreStatesReplaceOnlyPendingOrFailedEmptyStates() {
        #expect(CloudSyncInitialRestoreState.waitingForCloud.shouldReplaceEmptyState)
        #expect(CloudSyncInitialRestoreState.restoring.shouldReplaceEmptyState)
        #expect(CloudSyncInitialRestoreState.failed(message: "Failure").shouldReplaceEmptyState)
        #expect(CloudSyncInitialRestoreState.notRequired.shouldReplaceEmptyState == false)
        #expect(CloudSyncInitialRestoreState.restored.shouldReplaceEmptyState == false)
    }

    private static func makeContext() throws -> TestContext {
        let databasePath: String = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrowseCraftCloudSyncSettingsTests-\(UUID().uuidString).sqlite")
            .path
        let database: AppDatabase = try AppDatabase(path: databasePath)
        let cloudScope: CloudAccountScope = .cloud(hash: "account-a")
        let activeScope: ActiveAccountScopeStore = ActiveAccountScopeStore()
        let stateProvider: MockCloudAccountStateProvider = MockCloudAccountStateProvider(
            state: CloudAccountState(availability: .available, scope: cloudScope)
        )
        let preferences: MockCloudSyncPreferenceStore = MockCloudSyncPreferenceStore()
        let accountSession: CloudAccountSession = CloudAccountSession(
            stateProvider: stateProvider,
            preferenceStore: preferences,
            activeScopeStore: activeScope
        )
        let cloudStore: MockCloudRecordStore = MockCloudRecordStore()
        let partitionStore: GRDBCloudAccountPartitionStore = GRDBCloudAccountPartitionStore(
            database: database
        )
        let sourceSyncLocalStore: GRDBSourceSyncLocalStore = GRDBSourceSyncLocalStore(
            database: database
        )
        let coordinator: CloudSyncCoordinator = CloudSyncCoordinator(
            accountSession: accountSession,
            sourceService: SourceSyncService(
                localStore: sourceSyncLocalStore,
                cloudStore: cloudStore,
                accountScopeProvider: activeScope
            ),
            favoriteItemService: FavoriteItemSyncService(
                localStore: GRDBFavoriteItemSyncLocalStore(database: database),
                cloudStore: cloudStore,
                accountScopeProvider: activeScope
            ),
            cloudStore: cloudStore,
            changeNotifier: CloudSyncChangeNotifier(),
            partitionStore: partitionStore
        )
        return TestContext(
            cloudScope: cloudScope,
            activeScope: activeScope,
            stateProvider: stateProvider,
            preferences: preferences,
            accountSession: accountSession,
            partitionStore: partitionStore,
            coordinator: coordinator,
            cloudStore: cloudStore,
            sourceSyncLocalStore: sourceSyncLocalStore,
            sourceRepository: GRDBSourceRepository(
                database: database,
                accountScopeProvider: activeScope
            )
        )
    }

    private static func makeSource() -> Source {
        let now: Date = Date(timeIntervalSince1970: 100)
        return Source(
            id: "source-1",
            name: "Source",
            baseURL: "https://example.test",
            type: .rss,
            configuration: .rss(
                RSSSourceConfiguration(
                    definition: RSSSourceDefinition(
                        feedURL: URL(string: "https://example.test/feed.xml")!,
                        requiresAccount: false,
                        refreshPolicy: .manual
                    )
                )
            ),
            enabled: true,
            createdAt: now,
            updatedAt: now
        )
    }
}

private struct TestContext {
    var cloudScope: CloudAccountScope
    var activeScope: ActiveAccountScopeStore
    var stateProvider: MockCloudAccountStateProvider
    var preferences: MockCloudSyncPreferenceStore
    var accountSession: CloudAccountSession
    var partitionStore: GRDBCloudAccountPartitionStore
    var coordinator: CloudSyncCoordinator
    var cloudStore: MockCloudRecordStore
    var sourceSyncLocalStore: GRDBSourceSyncLocalStore
    var sourceRepository: GRDBSourceRepository

    @MainActor
    func makeViewModel() -> CloudSyncSettingsViewModel {
        return CloudSyncSettingsViewModel(
            accountSession: self.accountSession,
            partitionStore: self.partitionStore,
            coordinator: self.coordinator
        )
    }
}
