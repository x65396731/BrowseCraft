import Combine
import Foundation

@MainActor
final class CloudSyncSettingsViewModel: ObservableObject {
    enum ActivationIssue: String, Hashable, Identifiable {
        case signInRequired
        case restricted
        case temporarilyUnavailable
        case statusUnavailable

        var id: String {
            return self.rawValue
        }
    }

    struct FirstEnableRequest: Hashable, Identifiable {
        var cloudScope: CloudAccountScope
        var localDataSummary: CloudAccountPartitionSummary

        var id: String {
            return self.cloudScope.rawValue
        }
    }

    @Published private(set) var accountSnapshot: CloudAccountSessionSnapshot
    @Published private(set) var coordinatorSnapshot: CloudSyncCoordinatorSnapshot
    @Published private(set) var preparation: CloudAccountPartitionPreparation?
    @Published private(set) var localDefaultSummary: CloudAccountPartitionSummary?
    @Published private(set) var firstEnableRequest: FirstEnableRequest?
    @Published private(set) var activationIssue: ActivationIssue?
    @Published private(set) var isRefreshingAccount: Bool = false
    @Published private(set) var isChangingCloudSyncEnabled: Bool = false
    @Published private(set) var isRequestingManualSync: Bool = false
    @Published private(set) var actionErrorMessage: String?
    @Published private(set) var initialRestoreState: CloudSyncInitialRestoreState = .notRequired
    @Published private(set) var contentRevision: UInt64 = 0

    private let accountSession: CloudAccountSession
    private let partitionStore: any CloudAccountPartitioning
    private let coordinator: CloudSyncCoordinator

    private var isStarted: Bool = false
    private var accountObservationTask: Task<Void, Never>?
    private var coordinatorObservationTask: Task<Void, Never>?
    private var lastHandledDownloadCheckpoint: CloudSyncDownloadCheckpoint?

    init(
        accountSession: CloudAccountSession,
        partitionStore: any CloudAccountPartitioning,
        coordinator: CloudSyncCoordinator
    ) {
        self.accountSession = accountSession
        self.partitionStore = partitionStore
        self.coordinator = coordinator
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
        return self.accountSnapshot.isSynchronizationEnabled && self.isSynchronizing == false
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

    func setCloudSyncEnabled(_ enabled: Bool) async {
        guard self.isChangingCloudSyncEnabled == false else {
            return
        }
        self.isChangingCloudSyncEnabled = true
        self.actionErrorMessage = nil
        self.activationIssue = nil
        defer {
            self.isChangingCloudSyncEnabled = false
        }

        if enabled == false {
            self.firstEnableRequest = nil
            await self.accountSession.setCloudSyncEnabled(false)
            await self.applyAccountSnapshot(self.accountSession.snapshot())
            return
        }

        await self.accountSession.refreshForUserInitiatedAccess()
        let snapshot: CloudAccountSessionSnapshot = await self.accountSession.snapshot()
        await self.applyAccountSnapshot(snapshot)

        guard let cloudScope: CloudAccountScope = snapshot.state.synchronizationScope else {
            self.activationIssue = self.activationIssue(for: snapshot.state.availability)
            return
        }

        do {
            if let preparation: CloudAccountPartitionPreparation = try self.partitionStore.preparation(
                for: cloudScope
            ) {
                self.preparation = preparation
                await self.enablePreparedCloudScope(cloudScope)
                return
            }

            let summary: CloudAccountPartitionSummary = try self.partitionStore.localDefaultSummary()
            self.localDefaultSummary = summary
            self.firstEnableRequest = FirstEnableRequest(
                cloudScope: cloudScope,
                localDataSummary: summary
            )
        } catch {
            self.actionErrorMessage = "Cloud sync setup could not be saved."
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
            self.firstEnableRequest = nil
            self.actionErrorMessage = "The iCloud account changed before setup was completed."
            return
        }

        do {
            _ = try self.partitionStore.prepareCloudScope(
                request.cloudScope,
                decision: decision
            )
            self.preparation = try self.partitionStore.preparation(for: request.cloudScope)
            self.localDefaultSummary = nil
            self.firstEnableRequest = nil
            self.contentRevision &+= 1
            await self.enablePreparedCloudScope(request.cloudScope)
        } catch {
            await self.loadPartitionState(for: snapshot)
            self.actionErrorMessage = "Cloud sync setup could not be saved."
        }
    }

    func cancelFirstEnable() {
        self.firstEnableRequest = nil
    }

    func dismissActivationIssue() {
        self.activationIssue = nil
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

        if snapshot.state.availability == .available {
            self.activationIssue = nil
        }

        if let request: FirstEnableRequest = self.firstEnableRequest,
           request.cloudScope != snapshot.state.synchronizationScope {
            self.firstEnableRequest = nil
        }

        await self.loadPartitionState(for: snapshot)
        if didChangeIdentity {
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
            self.localDefaultSummary = nil
            self.updateInitialRestoreState()
            return
        }
        let cloudScope: CloudAccountScope = snapshot.state.scope

        do {
            self.preparation = try self.partitionStore.preparation(for: cloudScope)
            self.localDefaultSummary = snapshot.state.availability == .available && self.preparation == nil
                ? try self.partitionStore.localDefaultSummary()
                : nil
            self.actionErrorMessage = nil
        } catch {
            self.preparation = nil
            self.localDefaultSummary = nil
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
}

private struct AccountIdentity: Hashable {
    var scope: CloudAccountScope
    var generation: UInt64
}
