import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft
import BrowseCraftDomain

@MainActor
struct CloudSyncSettingsViewModelTests {
    @Test func openingSettingsDoesNotReadOrCreateCloudIdentity() async throws {
        let context: TestContext = try await Self.makeContext()
        let viewModel: CloudSyncSettingsViewModel = context.makeViewModel()

        await viewModel.start()

        let fetchCallCount: Int = await context.identityStore.fetchCallCount()
        let createCallCount: Int = await context.identityStore.createCallCount()
        #expect(fetchCallCount == 0)
        #expect(createCallCount == 0)
        #expect(viewModel.cloudIdentityAssociationState == .notAssociated)
    }

    @Test func identityLinkButtonDoesNotEnableContentSync() async throws {
        let context: TestContext = try await Self.makeContext()
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
        let context: TestContext = try await Self.makeContext()
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
        let context: TestContext = try await Self.makeContext()
        let cloudIdentity: CloudAppUserIdentity = .proposed(
            userID: UUID(),
            at: Date(timeIntervalSince1970: 1)
        )
        await context.identityStore.setIdentity(cloudIdentity)
        let viewModel: CloudSyncSettingsViewModel = context.makeViewModel()
        await viewModel.start()

        await viewModel.setCloudSyncEnabled(true)

        // 中文注释：按同一个本地化键比对，不依赖模拟器语言（此前硬写英文，设置页三语补齐后在中文环境必失败）。
        #expect(
            viewModel.actionErrorMessage == NSLocalizedString(
                "This iCloud data belongs to another BrowseCraft account. Sign in with the matching Apple account before enabling Cloud Sync.",
                comment: ""
            )
        )
        #expect(viewModel.firstEnableRequest == nil)
        #expect(viewModel.isCloudSyncEnabled == false)
        let createCallCount: Int = await context.identityStore.createCallCount()
        let storedIdentity: CloudAppUserIdentity? =
            await context.identityStore.storedIdentity()
        #expect(createCallCount == 0)
        #expect(storedIdentity == cloudIdentity)
    }

    @Test func cloudConflictCannotAdoptAnUnauthenticatedUUID() async throws {
        let context: TestContext = try await Self.makeContext()
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

    /// 中文注释：备忘录「未登录不能创建或关联 AppUserIdentity/default」——没有 Portal 会话时不读、不建云端身份记录，开关保持关闭。
    @Test func enablingCloudSyncWithoutPortalSessionIsRefused() async throws {
        let context: TestContext = try await Self.makeContext(portalSignedIn: false)
        let viewModel: CloudSyncSettingsViewModel = context.makeViewModel()
        await viewModel.start()
        await viewModel.setCloudSyncEnabled(true)

        let createCallCount: Int = await context.identityStore.createCallCount()
        let storedIdentity: CloudAppUserIdentity? = await context.identityStore.storedIdentity()
        #expect(createCallCount == 0)
        #expect(storedIdentity == nil)
        #expect(viewModel.isCloudSyncEnabled == false)
        #expect(viewModel.cloudIdentityAssociationState == .notAssociated)
        #expect(viewModel.actionErrorMessage != nil)
    }

    /// 中文注释：清理路径——云端记录是本机早先未登录时写上去的临时 UUID（本机 `app_users` 有行、从未作为 Portal 用户出现），
    /// 登录后开同步用当前后端 UUID 覆盖它，不再要求用户「换账户登录」。
    @Test func formerLocalIdentityInCloudIsReplacedByThePortalUser() async throws {
        let context: TestContext = try await Self.makeContext()
        let formerLocalUserID: UUID = UUID()
        try await context.database.queue.write { database in
            try AppUserRecord.insertUser(id: formerLocalUserID.uuidString, in: database)
        }
        let staleIdentity: CloudAppUserIdentity = .proposed(
            userID: formerLocalUserID,
            at: Date(timeIntervalSince1970: 1)
        )
        await context.identityStore.setIdentity(staleIdentity)
        let viewModel: CloudSyncSettingsViewModel = context.makeViewModel()
        await viewModel.start()
        await viewModel.setCloudSyncEnabled(true)

        let replaceCallCount: Int = await context.identityStore.replaceCallCount()
        let storedIdentity: CloudAppUserIdentity? = await context.identityStore.storedIdentity()
        #expect(replaceCallCount == 1)
        #expect(storedIdentity?.userID == context.activeAppUser.currentUserID)
        #expect(storedIdentity?.createdAt == staleIdentity.createdAt)
        if case .associated(let identity) = viewModel.cloudIdentityAssociationState {
            #expect(identity.userID == context.activeAppUser.currentUserID)
        } else {
            Issue.record("expected associated state, got \(viewModel.cloudIdentityAssociationState)")
        }
    }

    /// 中文注释：本机登录过的另一个 Portal 账户：`app_users` 有行但来源标记为 Portal，不走覆盖，仍交用户裁定。
    @Test func anotherPortalUserSeenOnThisDeviceIsNotReplaced() async throws {
        let context: TestContext = try await Self.makeContext()
        let otherPortalUserID: UUID = UUID()
        try await context.database.queue.write { database in
            try AppUserRecord.insertUser(id: otherPortalUserID.uuidString, in: database)
        }
        try context.identityOriginStore.markPortalUserID(otherPortalUserID)
        let cloudIdentity: CloudAppUserIdentity = .proposed(
            userID: otherPortalUserID,
            at: Date(timeIntervalSince1970: 1)
        )
        await context.identityStore.setIdentity(cloudIdentity)
        let viewModel: CloudSyncSettingsViewModel = context.makeViewModel()
        await viewModel.start()
        await viewModel.setCloudSyncEnabled(true)

        let replaceCallCount: Int = await context.identityStore.replaceCallCount()
        #expect(replaceCallCount == 0)
        #expect(viewModel.cloudIdentityAssociationState == .requiresUserDecision(
            localUserID: context.activeAppUser.currentUserID,
            cloudIdentity: cloudIdentity
        ))
        #expect(viewModel.isCloudSyncEnabled == false)
    }

    @Test func enablingWithLocalDataWaitsForAFirstEnableDecision() async throws {
        let context: TestContext = try await Self.makeContext()
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
        let context: TestContext = try await Self.makeContext()
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
        let context: TestContext = try await Self.makeContext()
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
        let context: TestContext = try await Self.makeContext()
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
        let context: TestContext = try await Self.makeContext()
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
        let context: TestContext = try await Self.makeContext()
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
        let context: TestContext = try await Self.makeContext()
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
        let context: TestContext = try await Self.makeContext()
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
        let context: TestContext = try await Self.makeContext()
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
        let context: TestContext = try await Self.makeContext()
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
        let context: TestContext = try await Self.makeContext()
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
        let context: TestContext = try await Self.makeContext()
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

    private static func makeContext(portalSignedIn: Bool = true) async throws -> TestContext {
        let databasePath: String = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrowseCraftCloudSyncSettingsTests-\(UUID().uuidString).sqlite")
            .path
        let database: AppDatabase = try AppDatabase(path: databasePath)
        try await database.queue.write { database in
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
        try await database.queue.write { database in
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
        // 中文注释：缺省是已登录 Portal 的会话（用户 = 活动用户）；`portalSignedIn: false` 模拟未登录开同步。
        let portalSession: PortalSessionPersistence? = portalSignedIn
            ? PortalSessionPersistence(
                userID: activeAppUser.currentUserID,
                credentials: PortalAuthenticationTokens(
                    userID: activeAppUser.currentUserID,
                    accessToken: "access-token",
                    refreshToken: "refresh-token",
                    accessTokenExpiresAt: Date().addingTimeInterval(3_600),
                    refreshTokenExpiresAt: Date().addingTimeInterval(86_400)
                )
            )
            : nil
        let portalSessionStore: CloudSyncTestPortalSessionStore =
            CloudSyncTestPortalSessionStore(session: portalSession)
        let portalAuthenticator: CloudSyncTestPortalAuthenticator =
            CloudSyncTestPortalAuthenticator()
        let identityOriginStore: CloudSyncTestIdentityOriginStore = CloudSyncTestIdentityOriginStore()
        // 中文注释：关联协调器的 Portal 门禁读的是会话协调器已加载的会话，所以这里要 `start()` 一次。
        let portalSessionCoordinator: PortalSessionCoordinator = PortalSessionCoordinator(
            activeAppUser: activeAppUser,
            sessionStore: portalSessionStore,
            authenticator: portalAuthenticator,
            identityOriginStore: identityOriginStore
        )
        await portalSessionCoordinator.start()
        let identityAssociationCoordinator:
            CloudAppUserIdentityAssociationCoordinator =
            CloudAppUserIdentityAssociationCoordinator(
                identityStore: identityStore,
                activeAppUser: activeAppUser,
                portalSessionCoordinator: portalSessionCoordinator,
                appUserRepository: GRDBAppUserRepository(database: database),
                identityOriginStore: identityOriginStore,
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
            database: database,
            cloudScope: cloudScope,
            activeScope: activeScope,
            activeAppUser: activeAppUser,
            identityStore: identityStore,
            identityOriginStore: identityOriginStore,
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
            type: .html,
            configuration: TestSourceFixtures.pluginConfiguration(),
            enabled: true,
            createdAt: now,
            updatedAt: now
        )
    }
}

private struct TestContext {
    var database: AppDatabase
    var cloudScope: CloudAccountScope
    var activeScope: ActiveAccountScopeStore
    var activeAppUser: ActiveAppUserStore
    var identityStore: MockCloudAppUserIdentityStore
    var identityOriginStore: CloudSyncTestIdentityOriginStore
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

/// 中文注释：本机见过的 Portal 用户集合；关联协调器据此区分「本机旧本地 UUID」与「别的账户的后端 UUID」。
private final class CloudSyncTestIdentityOriginStore:
    PortalAppUserIdentityOriginStoring,
    @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private var portalUserIDs: Set<UUID> = []

    func containsPortalUserID(_ userID: UUID) throws -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.portalUserIDs.contains(userID)
    }

    func markPortalUserID(_ userID: UUID) throws {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.portalUserIDs.insert(userID)
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
    private var replaceCalls: Int = 0

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

    func replaceIdentity(
        _ identity: CloudAppUserIdentity,
        replacing existing: CloudAppUserIdentity
    ) async throws -> CloudAppUserIdentity {
        self.replaceCalls += 1
        guard self.identity?.userID == existing.userID else {
            throw CloudAppUserIdentityStoreError.operationFailed
        }
        self.identity = identity
        return identity
    }

    func replaceCallCount() -> Int {
        return self.replaceCalls
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
