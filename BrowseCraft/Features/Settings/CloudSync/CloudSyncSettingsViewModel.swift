import Observation
import Combine
import Foundation

@MainActor
@Observable
final class CloudSyncSettingsViewModel {
    enum ActivationIssue: String, Hashable, Identifiable {
        case signInRequired
        case restricted
        case temporarilyUnavailable
        case statusUnavailable

        var id: String {
            return self.rawValue
        }
    }

    private enum ActivationIntent: Equatable {
        case linkIdentity
        case enableCloudSync
    }

    struct FirstEnableRequest: Hashable, Identifiable {
        var cloudScope: CloudAccountScope
        var localDataSummary: CloudAccountPartitionSummary

        var id: String {
            return self.cloudScope.rawValue
        }
    }

    enum SetupRequest: Hashable, Identifiable {
        case firstEnable(FirstEnableRequest)

        var id: String {
            switch self {
            case .firstEnable(let request):
                return "first-enable:\(request.id)"
            }
        }

        var cloudScope: CloudAccountScope {
            switch self {
            case .firstEnable(let request):
                return request.cloudScope
            }
        }
    }

    private(set) var accountSnapshot: CloudAccountSessionSnapshot
    private(set) var coordinatorSnapshot: CloudSyncCoordinatorSnapshot
    private(set) var preparation: CloudAccountPartitionPreparation?
    private(set) var currentUserSummary: CloudAccountPartitionSummary?
    private(set) var setupRequest: SetupRequest?
    private(set) var cloudIdentityAssociationState:
        CloudAppUserIdentityAssociationState = .notAssociated
    private(set) var activationIssue: ActivationIssue?
    private(set) var isRefreshingAccount: Bool = false
    private(set) var isChangingCloudSyncEnabled: Bool = false
    private(set) var isRequestingManualSync: Bool = false
    private(set) var actionErrorMessage: String?
    private(set) var initialRestoreState: CloudSyncInitialRestoreState = .notRequired
    private(set) var contentRevision: UInt64 = 0
    private(set) var identityRevision: UInt64 = 0
    private(set) var hasAttestedIdentityAssociation: Bool = false

    private let accountSession: CloudAccountSession
    private let partitionStore: any CloudAccountPartitioning
    private let coordinator: CloudSyncCoordinator
    private let identityAssociationCoordinator: CloudAppUserIdentityAssociationCoordinator
    private let associationAttestationStore:
        (any CloudAppUserAssociationAttestationStoring)?
    private let activeAppUser: (any ActiveAppUserProviding)?

    private var isStarted: Bool = false
    /// 中文注释：任务句柄不是界面状态，且 deinit 需要直接触碰存储属性——排除观察。
    @ObservationIgnored
    private var accountObservationTask: Task<Void, Never>?
    /// 中文注释：任务句柄不是界面状态，且 deinit 需要直接触碰存储属性——排除观察。
    @ObservationIgnored
    private var coordinatorObservationTask: Task<Void, Never>?
    private var lastHandledDownloadCheckpoint: CloudSyncDownloadCheckpoint?
    private var activationIntent: ActivationIntent?

    init(
        accountSession: CloudAccountSession,
        partitionStore: any CloudAccountPartitioning,
        coordinator: CloudSyncCoordinator,
        identityAssociationCoordinator: CloudAppUserIdentityAssociationCoordinator,
        associationAttestationStore:
            (any CloudAppUserAssociationAttestationStoring)? = nil,
        activeAppUser: (any ActiveAppUserProviding)? = nil
    ) {
        self.accountSession = accountSession
        self.partitionStore = partitionStore
        self.coordinator = coordinator
        self.identityAssociationCoordinator = identityAssociationCoordinator
        self.associationAttestationStore = associationAttestationStore
        self.activeAppUser = activeAppUser
        self.hasAttestedIdentityAssociation =
            associationAttestationStore == nil
        self.accountSnapshot = CloudAccountSessionSnapshot(
            state: .initial,
            generation: 0,
            accountPreferenceEnabled: false
        )
        self.coordinatorSnapshot = .initial
    }

    deinit {
        self.accountObservationTask?.cancel()
        self.coordinatorObservationTask?.cancel()
    }

    var accountAvailability: CloudAccountAvailability {
        return self.accountSnapshot.state.availability
    }

    var firstEnableRequest: FirstEnableRequest? {
        guard case .some(.firstEnable(let request)) = self.setupRequest else {
            return nil
        }
        return request
    }

    var isCloudSyncEnabled: Bool {
        return self.accountSnapshot.accountPreferenceEnabled
    }

    var canChangeCloudSyncEnabled: Bool {
        return self.isRefreshingAccount == false &&
            self.isChangingCloudSyncEnabled == false
    }

    var isSynchronizing: Bool {
        return self.isRequestingManualSync || self.coordinatorSnapshot.isSynchronizing
    }

    var canSynchronizeNow: Bool {
        return self.accountSnapshot.isSynchronizationEnabled &&
            self.hasAttestedIdentityAssociation &&
            self.isSynchronizing == false
    }

    var lastResult: CloudSyncRunResult? {
        guard self.coordinatorSnapshot.lastResult?.accountScope == self.accountSnapshot.state.scope else {
            return nil
        }
        return self.coordinatorSnapshot.lastResult
    }

    var errorMessage: String? {
        if let actionErrorMessage: String = self.actionErrorMessage {
            return actionErrorMessage
        }
        guard self.coordinatorSnapshot.lastErrorAccountScope == self.accountSnapshot.state.scope else {
            return nil
        }
        return self.coordinatorSnapshot.lastErrorMessage
    }

    func start() async {
        guard self.isStarted == false else {
            return
        }
        self.isStarted = true

        let accountUpdates: AsyncStream<CloudAccountSessionSnapshot> = await self.accountSession.updates()
        let coordinatorUpdates: AsyncStream<CloudSyncCoordinatorSnapshot> = await self.coordinator.updates()

        await self.applyAccountSnapshot(self.accountSession.snapshot())
        await self.applyCoordinatorSnapshot(self.coordinator.snapshot())

        self.accountObservationTask = Task { [weak self] in
            for await snapshot: CloudAccountSessionSnapshot in accountUpdates {
                guard Task.isCancelled == false else {
                    return
                }
                await self?.applyAccountSnapshot(snapshot)
            }
        }
        self.coordinatorObservationTask = Task { [weak self] in
            for await snapshot: CloudSyncCoordinatorSnapshot in coordinatorUpdates {
                guard Task.isCancelled == false else {
                    return
                }
                await self?.applyCoordinatorSnapshot(snapshot)
            }
        }
    }

    func stop() {
        self.accountObservationTask?.cancel()
        self.coordinatorObservationTask?.cancel()
        self.accountObservationTask = nil
        self.coordinatorObservationTask = nil
        self.isStarted = false
    }

    func refreshAccount() async {
        guard self.isRefreshingAccount == false else {
            return
        }
        self.isRefreshingAccount = true
        self.actionErrorMessage = nil
        defer {
            self.isRefreshingAccount = false
        }

        await self.accountSession.refreshForUserInitiatedAccess()
        await self.applyAccountSnapshot(self.accountSession.snapshot())
    }

    func linkCloudIdentity() async {
        guard self.isChangingCloudSyncEnabled == false else {
            return
        }
        CloudSyncDiagnostics.logIdentityChange(
            event: "manual-link-button-tapped"
        )
        self.isChangingCloudSyncEnabled = true
        self.actionErrorMessage = nil
        self.activationIssue = nil
        self.activationIntent = .linkIdentity
        self.setupRequest = nil
        defer {
            self.isChangingCloudSyncEnabled = false
        }

        guard let cloudScope: CloudAccountScope =
            await self.userInitiatedCloudScope() else {
            return
        }

        do {
            _ = try await self.associateIdentity(for: cloudScope)
            self.activationIntent = nil
        } catch {
            CloudSyncDiagnostics.logIdentityAssociationFailed(
                stage: "manual-link-ui",
                error: error
            )
            self.cloudIdentityAssociationState = .notAssociated
            self.activationIntent = nil
            self.actionErrorMessage = Self.setupErrorMessage(for: error)
        }
    }

    func setCloudSyncEnabled(_ enabled: Bool) async {
        guard self.isChangingCloudSyncEnabled == false else {
            return
        }
        self.isChangingCloudSyncEnabled = true
        self.actionErrorMessage = nil
        self.activationIssue = nil
        self.activationIntent = enabled ? .enableCloudSync : nil
        self.setupRequest = nil
        defer {
            self.isChangingCloudSyncEnabled = false
        }

        if enabled == false {
            self.setupRequest = nil
            await self.accountSession.setCloudSyncEnabled(false)
            await self.applyAccountSnapshot(self.accountSession.snapshot())
            return
        }

        guard let cloudScope: CloudAccountScope =
            await self.userInitiatedCloudScope() else {
            return
        }

        do {
            guard try await self.associateIdentity(for: cloudScope) else {
                return
            }
            self.activationIntent = nil

            if let preparation: CloudAccountPartitionPreparation = try self.partitionStore.preparation(
                for: cloudScope
            ) {
                self.preparation = preparation
                await self.enablePreparedCloudScope(cloudScope)
                return
            }

            let summary: CloudAccountPartitionSummary = try self.partitionStore.currentUserSummary()
            self.currentUserSummary = summary
            self.setupRequest = .firstEnable(
                FirstEnableRequest(
                    cloudScope: cloudScope,
                    localDataSummary: summary
                )
            )
        } catch {
            CloudSyncDiagnostics.logIdentityAssociationFailed(
                stage: "enable-cloud-sync",
                error: error
            )
            self.cloudIdentityAssociationState = .notAssociated
            self.activationIntent = nil
            self.actionErrorMessage = Self.setupErrorMessage(for: error)
        }
    }

    func confirmFirstEnable(decision: CloudAccountLocalDataDecision) async {
        guard let request: FirstEnableRequest = self.firstEnableRequest else {
            return
        }
        self.actionErrorMessage = nil

        let snapshot: CloudAccountSessionSnapshot = await self.accountSession.snapshot()
        guard snapshot.state.availability == .available,
              snapshot.state.synchronizationScope == request.cloudScope else {
            self.setupRequest = nil
            self.actionErrorMessage = "The iCloud account changed before setup was completed."
            return
        }

        do {
            _ = try self.partitionStore.prepareCloudScope(
                request.cloudScope,
                decision: decision
            )
            self.preparation = try self.partitionStore.preparation(for: request.cloudScope)
            self.currentUserSummary = nil
            self.setupRequest = nil
            self.contentRevision &+= 1
            await self.enablePreparedCloudScope(request.cloudScope)
        } catch {
            await self.loadPartitionState(for: snapshot)
            self.actionErrorMessage = "Cloud sync setup could not be saved."
        }
    }

    func cancelFirstEnable() {
        guard case .some(.firstEnable(_)) = self.setupRequest else {
            return
        }
        self.setupRequest = nil
        self.currentUserSummary = nil
    }

    func dismissSetupRequest() {
        self.cancelFirstEnable()
    }

    func dismissActivationIssue() {
        self.activationIssue = nil
        self.activationIntent = nil
    }

    func retryActivation() async {
        switch self.activationIntent {
        case .linkIdentity:
            await self.linkCloudIdentity()
        case .enableCloudSync:
            await self.setCloudSyncEnabled(true)
        case nil:
            return
        }
    }

    func synchronizeNow() async {
        await self.runSynchronization(trigger: .manual)
    }

    func retrySynchronization() async {
        await self.runSynchronization(trigger: .retry)
    }

    private func runSynchronization(trigger: CloudSyncTrigger) async {
        guard self.isSynchronizing == false else {
            return
        }
        self.isRequestingManualSync = true
        self.actionErrorMessage = nil
        defer {
            self.isRequestingManualSync = false
        }

        do {
            _ = try await self.coordinator.synchronize(trigger: trigger)
            await self.applyCoordinatorSnapshot(self.coordinator.snapshot())
        } catch {
            if error is CancellationError {
                return
            }
            let snapshot: CloudSyncCoordinatorSnapshot = await self.coordinator.snapshot()
            await self.applyCoordinatorSnapshot(snapshot)
            if snapshot.lastErrorMessage == nil {
                self.actionErrorMessage = CloudSyncSafeErrorMessage.describe(error)
            }
        }
    }

    private func enablePreparedCloudScope(_ cloudScope: CloudAccountScope) async {
        let snapshot: CloudAccountSessionSnapshot = await self.accountSession.snapshot()
        guard snapshot.state.synchronizationScope == cloudScope else {
            self.actionErrorMessage = "The iCloud account changed before setup was completed."
            return
        }

        await self.accountSession.setCloudSyncEnabled(true)
        await self.applyAccountSnapshot(self.accountSession.snapshot())
    }

    private func activationIssue(
        for availability: CloudAccountAvailability
    ) -> ActivationIssue {
        switch availability {
        case .noAccount:
            return .signInRequired
        case .restricted:
            return .restricted
        case .temporarilyUnavailable:
            return .temporarilyUnavailable
        case .notChecked, .checking, .couldNotDetermine, .available:
            return .statusUnavailable
        }
    }

    private func userInitiatedCloudScope() async -> CloudAccountScope? {
        await self.accountSession.refreshForUserInitiatedAccess()
        let snapshot: CloudAccountSessionSnapshot = await self.accountSession.snapshot()
        await self.applyAccountSnapshot(snapshot)

        guard let cloudScope: CloudAccountScope = snapshot.state.synchronizationScope else {
            CloudSyncDiagnostics.logIdentityChange(
                event: "manual-access-unavailable-\(snapshot.state.availability.rawValue)"
            )
            self.activationIssue = self.activationIssue(for: snapshot.state.availability)
            return nil
        }
        return cloudScope
    }

    private func associateIdentity(
        for cloudScope: CloudAccountScope
    ) async throws -> Bool {
        let associationState: CloudAppUserIdentityAssociationState =
            try await self.identityAssociationCoordinator
                .associateForUserInitiatedAccess()
        self.cloudIdentityAssociationState = associationState

        switch associationState {
        case .associated(let identity):
            try self.associationAttestationStore?.attestAssociation(
                cloudScope: cloudScope,
                userID: identity.userID
            )
            CloudSyncDiagnostics.logIdentityAttestation(
                accountScope: cloudScope,
                outcome: "saved"
            )
            self.hasAttestedIdentityAssociation = true
            await self.coordinator.identityAssociationDidChange()
            return true
        case .requiresUserDecision(let localUserID, let cloudIdentity):
            CloudSyncDiagnostics.logIdentityAssociation(
                event: "portal-account-mismatch-blocked",
                localUserID: localUserID,
                cloudUserID: cloudIdentity.userID
            )
            self.actionErrorMessage =
                "This iCloud data belongs to another BrowseCraft account. " +
                "Sign in with the matching Apple account before enabling Cloud Sync."
            return false
        case .notAssociated, .readyToCreate:
            throw CloudAppUserIdentityAssociationError.unexpectedState
        }
    }

    private func applyAccountSnapshot(_ snapshot: CloudAccountSessionSnapshot) async {
        let previousIdentity: AccountIdentity = AccountIdentity(
            scope: self.accountSnapshot.state.scope,
            generation: self.accountSnapshot.generation
        )
        let newIdentity: AccountIdentity = AccountIdentity(
            scope: snapshot.state.scope,
            generation: snapshot.generation
        )
        let didChangeIdentity: Bool = previousIdentity != newIdentity
        self.accountSnapshot = snapshot
        self.loadAttestedIdentityAssociation(for: snapshot)

        if snapshot.state.availability == .available {
            self.activationIssue = nil
        }

        if let request: SetupRequest = self.setupRequest,
           request.cloudScope != snapshot.state.synchronizationScope {
            self.setupRequest = nil
        }

        await self.loadPartitionState(for: snapshot)
        if didChangeIdentity {
            self.setupRequest = nil
            if self.hasAttestedIdentityAssociation == false {
                self.cloudIdentityAssociationState = .notAssociated
            }
            self.contentRevision &+= 1
        }
    }

    private func applyCoordinatorSnapshot(_ snapshot: CloudSyncCoordinatorSnapshot) async {
        self.coordinatorSnapshot = snapshot

        if let checkpoint: CloudSyncDownloadCheckpoint = snapshot.lastDownloadCheckpoint,
           checkpoint != self.lastHandledDownloadCheckpoint {
            self.lastHandledDownloadCheckpoint = checkpoint

            if checkpoint.accountScope == self.accountSnapshot.state.scope {
                do {
                    self.preparation = try self.partitionStore.preparation(
                        for: checkpoint.accountScope
                    )
                } catch {
                    self.actionErrorMessage = "The initial iCloud restore status could not be saved."
                }
                self.contentRevision &+= 1
            }
        }

        self.updateInitialRestoreState()
    }

    private func loadPartitionState(for snapshot: CloudAccountSessionSnapshot) async {
        guard snapshot.state.scope.isCloud else {
            self.preparation = nil
            self.currentUserSummary = nil
            self.updateInitialRestoreState()
            return
        }
        let cloudScope: CloudAccountScope = snapshot.state.scope

        do {
            self.preparation = try self.partitionStore.preparation(for: cloudScope)
            self.currentUserSummary = snapshot.state.availability == .available && self.preparation == nil
                ? try self.partitionStore.currentUserSummary()
                : nil
            self.actionErrorMessage = nil
        } catch {
            self.preparation = nil
            self.currentUserSummary = nil
            self.actionErrorMessage = "Cloud sync setup could not be loaded."
        }
        self.updateInitialRestoreState()
    }

    private func updateInitialRestoreState() {
        let scope: CloudAccountScope = self.accountSnapshot.state.scope
        guard scope.isCloud,
              self.accountSnapshot.accountPreferenceEnabled else {
            self.initialRestoreState = .notRequired
            return
        }

        if self.preparation?.initialSyncCompletedAt != nil {
            self.initialRestoreState = .restored
            return
        }

        guard self.accountSnapshot.state.availability == .available else {
            self.initialRestoreState = .waitingForCloud
            return
        }

        if self.coordinatorSnapshot.lastErrorAccountScope == scope,
           let message: String = self.coordinatorSnapshot.lastErrorMessage {
            self.initialRestoreState = .failed(message: message)
        } else if self.coordinatorSnapshot.isSynchronizing || self.isRequestingManualSync {
            self.initialRestoreState = .restoring
        } else {
            self.initialRestoreState = .waitingForCloud
        }
    }

    private func loadAttestedIdentityAssociation(
        for snapshot: CloudAccountSessionSnapshot
    ) {
        guard let associationAttestationStore,
              let activeUserID: UUID = self.activeAppUser?.currentUserID,
              snapshot.state.scope.isCloud else {
            self.hasAttestedIdentityAssociation =
                self.associationAttestationStore == nil
            return
        }
        let associatedUserID: UUID? = try? associationAttestationStore
            .associatedUserID(for: snapshot.state.scope)
        self.hasAttestedIdentityAssociation =
            associatedUserID == activeUserID
        if self.hasAttestedIdentityAssociation {
            if case .associated(let identity) =
                self.cloudIdentityAssociationState,
               identity.userID == activeUserID {
                return
            }
            self.cloudIdentityAssociationState = .associated(
                identity: CloudAppUserIdentity(
                    userID: activeUserID,
                    createdAt: .distantPast,
                    updatedAt: .distantPast
                )
            )
        }
    }

    private static func setupErrorMessage(for error: any Error) -> String {
        if let storeError: CloudAppUserIdentityStoreError =
            error as? CloudAppUserIdentityStoreError {
            switch storeError {
            case .accountUnavailable:
                return "The iCloud account is not available for identity linking."
            case .accessDenied:
                return "BrowseCraft does not have permission to link this iCloud account."
            case .malformedRecord:
                return "The iCloud BrowseCraft identity record is invalid."
            case .unsupportedSchemaVersion:
                return "This iCloud BrowseCraft identity requires a newer app version."
            case .temporarilyUnavailable:
                return "iCloud identity linking is temporarily unavailable. Try again later."
            case .operationFailed:
                return "The iCloud BrowseCraft identity could not be linked."
            }
        }
        if let associationError: CloudAppUserIdentityAssociationError =
            error as? CloudAppUserIdentityAssociationError {
            switch associationError {
            case .activeUserChanged, .unexpectedState:
                return "The active BrowseCraft profile changed before iCloud linking completed."
            }
        }
        return "Cloud sync setup could not be saved."
    }

}

private struct AccountIdentity: Hashable {
    var scope: CloudAccountScope
    var generation: UInt64
}
