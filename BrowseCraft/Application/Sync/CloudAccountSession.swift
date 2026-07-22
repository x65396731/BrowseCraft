import Foundation

struct CloudAccountSessionSnapshot: Hashable, Sendable {
    var state: CloudAccountState
    var generation: UInt64
    var accountPreferenceEnabled: Bool

    var isSynchronizationEnabled: Bool {
        return self.state.synchronizationScope != nil && self.accountPreferenceEnabled
    }
}

/// 中文注释：CloudAccountSession 统一管理当前账户空间和切换世代，后续同步任务必须校验 generation。
actor CloudAccountSession {
    private let stateProvider: any CloudAccountStateProviding
    private let preferenceStore: any CloudSyncPreferenceStoring
    private let activeScopeStore: ActiveAccountScopeStore

    private var state: CloudAccountState = .initial
    private var generation: UInt64 = 0
    private var monitoringTask: Task<Void, Never>?
    private var continuations: [UUID: AsyncStream<CloudAccountSessionSnapshot>.Continuation] = [:]

    init(
        stateProvider: any CloudAccountStateProviding,
        preferenceStore: any CloudSyncPreferenceStoring,
        activeScopeStore: ActiveAccountScopeStore = ActiveAccountScopeStore()
    ) {
        self.stateProvider = stateProvider
        self.preferenceStore = preferenceStore
        self.activeScopeStore = activeScopeStore
    }

    func start() async {
        guard self.monitoringTask == nil else {
            return
        }

        let updates: AsyncStream<CloudAccountState> = await self.stateProvider.stateUpdates()
        self.monitoringTask = Task { [weak self] in
            for await state: CloudAccountState in updates {
                guard Task.isCancelled == false else {
                    return
                }
                await self?.apply(state)
            }
        }

        await self.stateProvider.startMonitoring()
        self.apply(await self.stateProvider.currentState())
    }

    /// 中文注释：只有用户曾主动开启 Cloud Sync，App 启动时才解析 CloudKit 账号身份。
    func startIfPreviouslyEnabled() async {
        guard self.preferenceStore.hasCloudSyncUserConsent() else {
            return
        }
        await self.start()
    }

    /// 中文注释：开关或刷新按钮属于用户主动行为，可在此时启动并刷新账户监听。
    func refreshForUserInitiatedAccess() async {
        if self.monitoringTask == nil {
            await self.start()
        } else {
            await self.refresh()
        }
    }

    func stop() async {
        self.monitoringTask?.cancel()
        self.monitoringTask = nil
        await self.stateProvider.stopMonitoring()
    }

    func refresh() async {
        await self.stateProvider.refresh()
        self.apply(await self.stateProvider.currentState())
    }

    func snapshot() -> CloudAccountSessionSnapshot {
        return self.makeSnapshot()
    }

    func updates() -> AsyncStream<CloudAccountSessionSnapshot> {
        let id: UUID = UUID()
        return AsyncStream { continuation in
            self.continuations[id] = continuation
            continuation.yield(self.makeSnapshot())
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeContinuation(id: id)
                }
            }
        }
    }

    func setCloudSyncEnabled(_ enabled: Bool) async {
        if enabled == false {
            if self.state.scope.isCloud {
                self.preferenceStore.setCloudSyncEnabled(false, for: self.state.scope)
            }
            self.preferenceStore.setCloudSyncUserConsent(false)
            self.publishSnapshot()
            await self.stop()
            return
        }

        guard self.state.availability == .available,
              self.state.scope.isCloud else {
            return
        }

        self.preferenceStore.setCloudSyncEnabled(true, for: self.state.scope)
        self.preferenceStore.setCloudSyncUserConsent(true)
        self.publishSnapshot()
    }

    private func apply(_ newState: CloudAccountState) {
        let oldSynchronizationScope: CloudAccountScope? = self.state.synchronizationScope
        let newSynchronizationScope: CloudAccountScope? = newState.synchronizationScope

        self.activeScopeStore.update(newState.scope)

        if oldSynchronizationScope != newSynchronizationScope {
            self.generation &+= 1
        }

        guard self.state != newState else {
            return
        }

        self.state = newState
        self.publishSnapshot()
    }

    private func makeSnapshot() -> CloudAccountSessionSnapshot {
        let preferenceEnabled: Bool = self.state.scope.isCloud &&
            self.preferenceStore.isCloudSyncEnabled(for: self.state.scope)
        return CloudAccountSessionSnapshot(
            state: self.state,
            generation: self.generation,
            accountPreferenceEnabled: preferenceEnabled
        )
    }

    private func publishSnapshot() {
        let snapshot: CloudAccountSessionSnapshot = self.makeSnapshot()
        for continuation: AsyncStream<CloudAccountSessionSnapshot>.Continuation in self.continuations.values {
            continuation.yield(snapshot)
        }
    }

    private func removeContinuation(id: UUID) {
        self.continuations.removeValue(forKey: id)
    }
}
