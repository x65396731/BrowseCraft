import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft

@MainActor
struct CloudSyncSettingsViewModelTests {
    @Test func openingSettingsDoesNotReadOrCreateCloudIdentity() async throws {
        let context: TestContext = try Self.makeContext()
        let viewModel: CloudSyncSettingsViewModel = context.makeViewModel()

        await viewModel.start()

        let fetchCallCount: Int = await context.identityStore.fetchCallCount()
        let createCallCount: Int = await context.identityStore.createCallCount()
        #expect(fetchCallCount == 0)
        #expect(createCallCount == 0)
        #expect(viewModel.cloudIdentityAssociationState == .notAssociated)
    }

    @Test func identityLinkButtonDoesNotEnableContentSync() async throws {
        let context: TestContext = try Self.makeContext()
        let viewModel: CloudSyncSettingsViewModel = context.makeViewModel()
        await viewModel.start()

        await viewModel.linkCloudIdentity()

        guard case .associated(let identity) = viewModel.cloudIdentityAssociationState else {
            Issue.record("Expected the explicit link action to associate the active profile")
            return
        }
        #expect(identity.userID == context.activeAppUser.currentUserID)
        #expect(viewModel.firstEnableRequest == nil)
        #expect(viewModel.isCloudSyncEnabled == false)
    }

    @Test func firstToggleStartsAccountAccessAndThenRequestsConfirmation() async throws {
        let context: TestContext = try Self.makeContext()
        let viewModel: CloudSyncSettingsViewModel = context.makeViewModel()
        await viewModel.start()

        #expect(viewModel.accountAvailability == .notChecked)

        await viewModel.setCloudSyncEnabled(true)

        let monitoringCalls: Int = await context.stateProvider.startMonitoringCallCount()
        #expect(monitoringCalls == 1)
        #expect(viewModel.accountAvailability == .available)
        #expect(viewModel.firstEnableRequest != nil)
        #expect(viewModel.isCloudSyncEnabled == false)
        let fetchCallCount: Int = await context.identityStore.fetchCallCount()
        let createCallCount: Int = await context.identityStore.createCallCount()
        #expect(fetchCallCount == 1)
        #expect(createCallCount == 1)
        guard case .associated(let identity) = viewModel.cloudIdentityAssociationState else {
            Issue.record("Expected the active profile to be linked before setup")
            return
        }
        #expect(identity.userID == context.activeAppUser.currentUserID)
    }

    @Test func differentCloudIdentityBlocksSyncWithoutOverwrite() async throws {
        let context: TestContext = try Self.makeContext()
        let cloudIdentity: CloudAppUserIdentity = .proposed(
            userID: UUID(),
            at: Date(timeIntervalSince1970: 1)
        )
        await context.identityStore.setIdentity(cloudIdentity)
        let viewModel: CloudSyncSettingsViewModel = context.makeViewModel()
        await viewModel.start()

        await viewModel.setCloudSyncEnabled(true)

        #expect(viewModel.actionErrorMessage?.contains("another BrowseCraft account") == true)
        #expect(viewModel.firstEnableRequest == nil)
        #expect(viewModel.isCloudSyncEnabled == false)
        let createCallCount: Int = await context.identityStore.createCallCount()
        let storedIdentity: CloudAppUserIdentity? =
            await context.identityStore.storedIdentity()
        #expect(createCallCount == 0)
        #expect(storedIdentity == cloudIdentity)
    }

    @Test func cloudConflictCannotAdoptAnUnauthenticatedUUID() async throws {
        let context: TestContext = try Self.makeContext()
        let cloudIdentity: CloudAppUserIdentity = .proposed(
            userID: UUID(),
            at: Date(timeIntervalSince1970: 1)
        )
        await context.identityStore.setIdentity(cloudIdentity)
        let viewModel: CloudSyncSettingsViewModel = context.makeViewModel()
        await viewModel.start()
        await viewModel.setCloudSyncEnabled(true)

        #expect(context.activeAppUser.currentUserID != cloudIdentity.userID)
        #expect(context.localIdentityStore.userID == context.activeAppUser.currentUserID)
        #expect(context.portalSessionStore.session?.userID == context.activeAppUser.currentUserID)
        #expect(viewModel.cloudIdentityAssociationState == .requiresUserDecision(
            localUserID: context.activeAppUser.currentUserID,
            cloudIdentity: cloudIdentity
        ))
        #expect(viewModel.isCloudSyncEnabled == false)
    }

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

    @Test func enablingWithoutLocalDataStillWaitsForExplicitConfirmation() async throws {
        let context: TestContext = try Self.makeContext()
        await context.accountSession.start()
        let viewModel: CloudSyncSettingsViewModel = context.makeViewModel()
        await viewModel.start()

        await viewModel.setCloudSyncEnabled(true)

        #expect(viewModel.firstEnableRequest?.localDataSummary.hasMergeableData == false)
        #expect(viewModel.isCloudSyncEnabled == false)

        await viewModel.confirmFirstEnable(decision: .useCloudDataOnly)

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
        await viewModel.confirmFirstEnable(decision: .useCloudDataOnly)
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

    @Test func choosingCloudOnlyClearsCurrentIdentityDataAcrossSyncScopes() async throws {
        let context: TestContext = try Self.makeContext()
        try context.sourceRepository.saveSource(Self.makeSource())
        await context.accountSession.start()
        let viewModel: CloudSyncSettingsViewModel = context.makeViewModel()
        await viewModel.start()
        await viewModel.setCloudSyncEnabled(true)

        await viewModel.confirmFirstEnable(decision: .useCloudDataOnly)

        #expect(try context.sourceRepository.fetchSources().isEmpty)
        context.activeScope.update(.localDefault)
        #expect(try context.sourceRepository.fetchSources().isEmpty)
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
        #expect(viewModel.canChangeCloudSyncEnabled)
        #expect(viewModel.canSynchronizeNow == false)
        #expect(viewModel.isCloudSyncEnabled == false)
        #expect(viewModel.initialRestoreState == .notRequired)
        #expect(viewModel.activationIssue == .signInRequired)
        #expect(viewModel.actionErrorMessage == nil)
    }

    @Test func temporaryAccountOutagePausesSyncButRetainsPreferenceAndPreparation() async throws {
        let context: TestContext = try Self.makeContext()
        await context.accountSession.start()
        let viewModel: CloudSyncSettingsViewModel = context.makeViewModel()
        await viewModel.start()
        await viewModel.setCloudSyncEnabled(true)
        await viewModel.confirmFirstEnable(decision: .useCloudDataOnly)
        await context.stateProvider.setState(
            CloudAccountState(
                availability: .temporarilyUnavailable,
                scope: context.cloudScope
            )
        )

        await viewModel.refreshAccount()

        #expect(viewModel.accountAvailability == .temporarilyUnavailable)
        #expect(viewModel.isCloudSyncEnabled)
        #expect(viewModel.canChangeCloudSyncEnabled)
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
        await viewModel.confirmFirstEnable(decision: .useCloudDataOnly)
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
        await viewModel.confirmFirstEnable(decision: .useCloudDataOnly)
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
        await viewModel.confirmFirstEnable(decision: .useCloudDataOnly)
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
        await viewModel.confirmFirstEnable(decision: .useCloudDataOnly)
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
        try database.queue.write { database in
            try AppUserRecord.insertLocalDefaultUser(in: database)
        }
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
        let activeAppUser: ActiveAppUserStore = ActiveAppUserStore(
            initialUserID: UUID()
        )
        try database.queue.write { database in
            try AppUserRecord.insertUser(
                id: activeAppUser.currentUserID.uuidString,
                in: database
            )
        }
        let identityStore: MockCloudAppUserIdentityStore =
            MockCloudAppUserIdentityStore()
        let localIdentityStore: CloudSyncTestAppUserIdentityStore =
            CloudSyncTestAppUserIdentityStore(
                userID: activeAppUser.currentUserID
            )
        let portalSessionStore: CloudSyncTestPortalSessionStore =
            CloudSyncTestPortalSessionStore(
                session: PortalSessionPersistence(
                    userID: activeAppUser.currentUserID,
                    credentials: PortalAuthenticationTokens(
                        userID: activeAppUser.currentUserID,
                        accessToken: "access-token",
                        refreshToken: "refresh-token",
                        accessTokenExpiresAt: Date().addingTimeInterval(3_600),
                        refreshTokenExpiresAt: Date().addingTimeInterval(86_400)
                    )
                )
            )
        let portalAuthenticator: CloudSyncTestPortalAuthenticator =
            CloudSyncTestPortalAuthenticator()
        let portalSessionCoordinator: PortalSessionCoordinator =
            PortalSessionCoordinator(
                activeAppUser: activeAppUser,
                sessionStore: portalSessionStore,
                authenticator: portalAuthenticator
            )
        let identityAssociationCoordinator:
            CloudAppUserIdentityAssociationCoordinator =
            CloudAppUserIdentityAssociationCoordinator(
                identityStore: identityStore,
                activeAppUser: activeAppUser,
                now: {
                    return Date(timeIntervalSince1970: 10)
                }
            )
        let partitionStore: GRDBCloudAccountPartitionStore = GRDBCloudAccountPartitionStore(
            database: database,
            activeAppUser: activeAppUser
        )
        let userContext: CloudSyncUserContext = CloudSyncUserContext()
        let sourceSyncLocalStore: GRDBSourceSyncLocalStore = GRDBSourceSyncLocalStore(
            database: database,
            activeAppUser: activeAppUser,
            userContext: userContext
        )
        let coordinator: CloudSyncCoordinator = CloudSyncCoordinator(
            accountSession: accountSession,
            sourceService: SourceSyncService(
                localStore: sourceSyncLocalStore,
                cloudStore: cloudStore,
                accountScopeProvider: activeScope
            ),
            favoriteItemService: FavoriteItemSyncService(
                localStore: GRDBFavoriteItemSyncLocalStore(
                    database: database,
                    activeAppUser: activeAppUser,
                    userContext: userContext
                ),
                cloudStore: cloudStore,
                activeAppUser: activeAppUser,
                userContext: userContext,
                accountScopeProvider: activeScope
            ),
            cloudStore: cloudStore,
            changeNotifier: CloudSyncChangeNotifier(),
            partitionStore: partitionStore,
            activeAppUser: activeAppUser,
            associationAttestationStore: partitionStore,
            userContext: userContext
        )
        return TestContext(
            cloudScope: cloudScope,
            activeScope: activeScope,
            activeAppUser: activeAppUser,
            identityStore: identityStore,
            identityAssociationCoordinator: identityAssociationCoordinator,
            localIdentityStore: localIdentityStore,
            portalSessionStore: portalSessionStore,
            portalAuthenticator: portalAuthenticator,
            stateProvider: stateProvider,
            preferences: preferences,
            accountSession: accountSession,
            partitionStore: partitionStore,
            coordinator: coordinator,
            cloudStore: cloudStore,
            sourceSyncLocalStore: sourceSyncLocalStore,
            sourceRepository: GRDBSourceRepository(
                database: database,
                activeAppUser: activeAppUser,
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
    var activeAppUser: ActiveAppUserStore
    var identityStore: MockCloudAppUserIdentityStore
    var identityAssociationCoordinator: CloudAppUserIdentityAssociationCoordinator
    var localIdentityStore: CloudSyncTestAppUserIdentityStore
    var portalSessionStore: CloudSyncTestPortalSessionStore
    var portalAuthenticator: CloudSyncTestPortalAuthenticator
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
            coordinator: self.coordinator,
            identityAssociationCoordinator: self.identityAssociationCoordinator,
            associationAttestationStore: self.partitionStore,
            activeAppUser: self.activeAppUser
        )
    }
}

private final class CloudSyncTestAppUserIdentityStore:
    AppUserIdentityStoring,
    @unchecked Sendable {
    private(set) var userID: UUID?

    init(userID: UUID?) {
        self.userID = userID
    }

    func loadUserID() throws -> UUID? {
        return self.userID
    }

    func saveUserID(_ userID: UUID) throws {
        self.userID = userID
    }
}

private final class CloudSyncTestPortalSessionStore:
    PortalSessionStoring,
    @unchecked Sendable {
    private(set) var session: PortalSessionPersistence?

    init(session: PortalSessionPersistence? = nil) {
        self.session = session
    }

    func load() throws -> PortalSessionPersistence? {
        return self.session
    }

    func save(_ session: PortalSessionPersistence) throws {
        self.session = session
    }

    func clear() throws {
        self.session = nil
    }
}

private actor CloudSyncTestPortalAuthenticator: PortalIdentityAuthenticating {
    private(set) var refreshCallCount: Int = 0

    func issueAppleChallenge() async throws -> PortalAppleAuthenticationChallenge {
        throw PortalIdentityAuthenticationError.temporarilyUnavailable
    }

    func authenticateWithApple(
        identityToken: String,
        nonce: String
    ) async throws -> PortalAuthenticationTokens {
        _ = identityToken
        _ = nonce
        throw PortalIdentityAuthenticationError.appleIdentityRejected
    }

    func refresh(refreshToken: String) async throws -> PortalAuthenticationTokens {
        self.refreshCallCount += 1
        throw PortalIdentityAuthenticationError.temporarilyUnavailable
    }

    func logout(refreshToken: String, accessToken: String) async throws {
        _ = refreshToken
        _ = accessToken
    }

    func logoutAll(accessToken: String) async throws {
        _ = accessToken
    }
}

private actor MockCloudAppUserIdentityStore: CloudAppUserIdentityStoring {
    private var identity: CloudAppUserIdentity?
    private var fetchCalls: Int = 0
    private var createCalls: Int = 0

    func fetchIdentity() async throws -> CloudAppUserIdentity? {
        self.fetchCalls += 1
        return self.identity
    }

    func createIdentityIfAbsent(
        _ proposedIdentity: CloudAppUserIdentity
    ) async throws -> CloudAppUserIdentity {
        self.createCalls += 1
        if let identity: CloudAppUserIdentity = self.identity {
            return identity
        }
        self.identity = proposedIdentity
        return proposedIdentity
    }

    func setIdentity(_ identity: CloudAppUserIdentity?) {
        self.identity = identity
    }

    func storedIdentity() -> CloudAppUserIdentity? {
        return self.identity
    }

    func fetchCallCount() -> Int {
        return self.fetchCalls
    }

    func createCallCount() -> Int {
        return self.createCalls
    }
}
