import Foundation

enum CloudSyncTrigger: String, Hashable, Sendable {
    case accountAvailable
    case localChange
    case foreground
    case remoteNotification
    case manual
    case retry
}

struct CloudSyncRunResult: Hashable, Sendable {
    var accountScope: CloudAccountScope
    var trigger: CloudSyncTrigger
    var sourceResult: SourceSyncResult
    var favoriteItemResult: FavoriteItemSyncResult
    var startedAt: Date
    var finishedAt: Date

    var uploadedCount: Int {
        return self.sourceResult.uploadedCount + self.favoriteItemResult.uploadedCount
    }

    var downloadedCount: Int {
        return self.sourceResult.downloadedCount + self.favoriteItemResult.downloadedCount
    }

    var deletedCount: Int {
        return self.sourceResult.deletedCount + self.favoriteItemResult.deletedCount
    }

    var failedCount: Int {
        return self.sourceResult.failedCount + self.favoriteItemResult.failedCount
    }

    var skippedCount: Int {
        return self.sourceResult.skippedCount + self.favoriteItemResult.skippedCount
    }
}

struct CloudSyncDownloadCheckpoint: Hashable, Sendable {
    var accountScope: CloudAccountScope
    var completedAt: Date
}

struct CloudSyncCoordinatorSnapshot: Hashable, Sendable {
    var isSynchronizing: Bool
    var activeTrigger: CloudSyncTrigger?
    var pendingTrigger: CloudSyncTrigger?
    var lastResult: CloudSyncRunResult?
    var lastErrorMessage: String?
    var lastErrorAccountScope: CloudAccountScope?
    var lastDownloadCheckpoint: CloudSyncDownloadCheckpoint?

    static let initial: CloudSyncCoordinatorSnapshot = CloudSyncCoordinatorSnapshot(
        isSynchronizing: false,
        activeTrigger: nil,
        pendingTrigger: nil,
        lastResult: nil,
        lastErrorMessage: nil,
        lastErrorAccountScope: nil,
        lastDownloadCheckpoint: nil
    )
}

/// 中文注释：所有自动与手动入口统一执行“下载全部 → 提交 engine state → 上传全部”。
actor CloudSyncCoordinator {
    private let accountSession: CloudAccountSession
    private let sourceService: SourceSyncService
    private let favoriteItemService: FavoriteItemSyncService
    private let cloudStore: any CloudRecordStore
    private let changeNotifier: any CloudSyncChangeNotifying
    private let partitionStore: any CloudAccountPartitioning

    private var accountMonitoringTask: Task<Void, Never>?
    private var localChangeTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var requestTask: Task<Void, Never>?
    private var pendingTrigger: CloudSyncTrigger?
    private var isRunning: Bool = false
    private var activeTrigger: CloudSyncTrigger?
    private var runningGeneration: UInt64?
    private var lastAutomaticallyRequestedKey: AutomaticRequestKey?
    private(set) var lastResult: CloudSyncRunResult?
    private(set) var lastErrorMessage: String?
    private var lastErrorAccountScope: CloudAccountScope?
    private var lastDownloadCheckpoint: CloudSyncDownloadCheckpoint?
    private var continuations: [UUID: AsyncStream<CloudSyncCoordinatorSnapshot>.Continuation] = [:]

    init(
        accountSession: CloudAccountSession,
        sourceService: SourceSyncService,
        favoriteItemService: FavoriteItemSyncService,
        cloudStore: any CloudRecordStore,
        changeNotifier: any CloudSyncChangeNotifying,
        partitionStore: any CloudAccountPartitioning
    ) {
        self.accountSession = accountSession
        self.sourceService = sourceService
        self.favoriteItemService = favoriteItemService
        self.cloudStore = cloudStore
        self.changeNotifier = changeNotifier
        self.partitionStore = partitionStore
    }

    func start() async {
        guard self.accountMonitoringTask == nil,
              self.localChangeTask == nil else {
            return
        }

        let accountUpdates: AsyncStream<CloudAccountSessionSnapshot> = await self.accountSession.updates()
        self.accountMonitoringTask = Task { [weak self] in
            for await snapshot: CloudAccountSessionSnapshot in accountUpdates {
                guard Task.isCancelled == false else {
                    return
                }
                await self?.handleAccountSnapshot(snapshot)
            }
        }

        let localChanges: AsyncStream<Void> = self.changeNotifier.changes()
        self.localChangeTask = Task { [weak self] in
            for await _: Void in localChanges {
                guard Task.isCancelled == false else {
                    return
                }
                await self?.scheduleDebouncedLocalChange()
            }
        }
    }

    func stop() async {
        self.accountMonitoringTask?.cancel()
        self.localChangeTask?.cancel()
        self.debounceTask?.cancel()
        self.requestTask?.cancel()
        self.accountMonitoringTask = nil
        self.localChangeTask = nil
        self.debounceTask = nil
        self.requestTask = nil
        self.pendingTrigger = nil
        await self.cloudStore.cancelOperations()
        self.publishSnapshot()
    }

    func snapshot() -> CloudSyncCoordinatorSnapshot {
        return self.makeSnapshot()
    }

    func updates() -> AsyncStream<CloudSyncCoordinatorSnapshot> {
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

    func requestSync(trigger: CloudSyncTrigger) {
        guard self.requestTask == nil,
              self.isRunning == false else {
            self.pendingTrigger = trigger
            self.publishSnapshot()
            return
        }
        self.requestTask = Task { [weak self] in
            guard let self else {
                return
            }
            do {
                _ = try await self.synchronize(trigger: trigger)
            } catch {}
            await self.finishRequest()
        }
        self.publishSnapshot()
    }

    func synchronize(
        trigger: CloudSyncTrigger,
        limit: Int = 100
    ) async throws -> CloudSyncRunResult {
        guard self.isRunning == false else {
            throw CloudSyncSessionError.alreadyRunning
        }
        let initialSnapshot: CloudAccountSessionSnapshot = await self.accountSession.snapshot()
        guard initialSnapshot.isSynchronizationEnabled,
              let accountScope: CloudAccountScope = initialSnapshot.state.synchronizationScope else {
            throw CloudSyncSessionError.synchronizationDisabled
        }

        self.isRunning = true
        self.activeTrigger = trigger
        self.runningGeneration = initialSnapshot.generation
        self.lastErrorMessage = nil
        self.lastErrorAccountScope = nil
        self.publishSnapshot()
        let startedAt: Date = Date()
        defer {
            self.isRunning = false
            self.activeTrigger = nil
            self.runningGeneration = nil
            self.publishSnapshot()
            self.startPendingRequestIfNeeded()
        }

        do {
            let sourceDownload: SourceSyncResult = try await self.sourceService.downloadSources(
                accountScope: accountScope
            )
            try await self.requireCurrentSession(initialSnapshot)

            let favoriteDownload: FavoriteItemSyncResult = try await self.favoriteItemService
                .downloadFavoriteItems(accountScope: accountScope)
            try await self.requireCurrentSession(initialSnapshot)

            try await self.cloudStore.commitState(for: accountScope)
            try await self.requireCurrentSession(initialSnapshot)

            let downloadCompletedAt: Date = Date()
            try self.partitionStore.markInitialSyncCompleted(
                for: accountScope,
                at: downloadCompletedAt
            )
            self.lastDownloadCheckpoint = CloudSyncDownloadCheckpoint(
                accountScope: accountScope,
                completedAt: downloadCompletedAt
            )
            self.publishSnapshot()

            let sourceUpload: SourceSyncResult = try await self.sourceService.uploadSources(
                accountScope: accountScope,
                limit: limit
            )
            try await self.requireCurrentSession(initialSnapshot)

            let favoriteUpload: FavoriteItemSyncResult = try await self.favoriteItemService
                .uploadFavoriteItems(accountScope: accountScope, limit: limit)
            try await self.requireCurrentSession(initialSnapshot)

            try await self.cloudStore.commitState(for: accountScope)
            try await self.requireCurrentSession(initialSnapshot)
            var sourceResult: SourceSyncResult = sourceDownload
            sourceResult.add(sourceUpload)
            var favoriteResult: FavoriteItemSyncResult = favoriteDownload
            favoriteResult.add(favoriteUpload)

            let result: CloudSyncRunResult = CloudSyncRunResult(
                accountScope: accountScope,
                trigger: trigger,
                sourceResult: sourceResult,
                favoriteItemResult: favoriteResult,
                startedAt: startedAt,
                finishedAt: Date()
            )
            self.lastResult = result
            self.lastErrorMessage = nil
            self.lastErrorAccountScope = nil
            self.publishSnapshot()
            return result
        } catch {
            // 中文注释：任何失败都丢弃尚未 checkpoint 的内存 engine state，下次从已提交状态重拉。
            await self.cloudStore.cancelOperations()
            self.record(error: error, accountScope: accountScope)
            throw error
        }
    }

    private func handleAccountSnapshot(_ snapshot: CloudAccountSessionSnapshot) async {
        if let runningGeneration: UInt64 = self.runningGeneration,
           runningGeneration != snapshot.generation || snapshot.isSynchronizationEnabled == false {
            await self.cloudStore.cancelOperations()
        }

        guard snapshot.isSynchronizationEnabled,
              let accountScope: CloudAccountScope = snapshot.state.synchronizationScope else {
            self.lastAutomaticallyRequestedKey = nil
            self.pendingTrigger = nil
            self.publishSnapshot()
            return
        }
        let key: AutomaticRequestKey = AutomaticRequestKey(
            accountScope: accountScope,
            generation: snapshot.generation
        )
        guard self.lastAutomaticallyRequestedKey != key else {
            return
        }
        self.lastAutomaticallyRequestedKey = key
        self.requestSync(trigger: .accountAvailable)
    }

    private func scheduleDebouncedLocalChange() {
        self.debounceTask?.cancel()
        self.debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard Task.isCancelled == false else {
                return
            }
            await self?.requestSync(trigger: .localChange)
        }
    }

    private func requireCurrentSession(
        _ initialSnapshot: CloudAccountSessionSnapshot
    ) async throws {
        let current: CloudAccountSessionSnapshot = await self.accountSession.snapshot()
        guard current.isSynchronizationEnabled,
              current.generation == initialSnapshot.generation,
              current.state.synchronizationScope == initialSnapshot.state.synchronizationScope else {
            throw CloudSyncSessionError.accountChanged
        }
    }

    private func record(error: any Error, accountScope: CloudAccountScope) {
        if let sessionError: CloudSyncSessionError = error as? CloudSyncSessionError,
           sessionError == .synchronizationDisabled || sessionError == .alreadyRunning {
            return
        }
        self.lastErrorMessage = CloudSyncSafeErrorMessage.describe(error)
        self.lastErrorAccountScope = accountScope
        self.publishSnapshot()
    }

    private func finishRequest() {
        self.requestTask = nil
        self.publishSnapshot()
        self.startPendingRequestIfNeeded()
    }

    private func startPendingRequestIfNeeded() {
        guard self.requestTask == nil,
              self.isRunning == false,
              let pendingTrigger: CloudSyncTrigger = self.pendingTrigger else {
            return
        }
        self.pendingTrigger = nil
        self.requestSync(trigger: pendingTrigger)
    }

    private func makeSnapshot() -> CloudSyncCoordinatorSnapshot {
        return CloudSyncCoordinatorSnapshot(
            isSynchronizing: self.isRunning || self.requestTask != nil,
            activeTrigger: self.activeTrigger,
            pendingTrigger: self.pendingTrigger,
            lastResult: self.lastResult,
            lastErrorMessage: self.lastErrorMessage,
            lastErrorAccountScope: self.lastErrorAccountScope,
            lastDownloadCheckpoint: self.lastDownloadCheckpoint
        )
    }

    private func publishSnapshot() {
        let snapshot: CloudSyncCoordinatorSnapshot = self.makeSnapshot()
        for continuation: AsyncStream<CloudSyncCoordinatorSnapshot>.Continuation in self.continuations.values {
            continuation.yield(snapshot)
        }
    }

    private func removeContinuation(id: UUID) {
        self.continuations.removeValue(forKey: id)
    }
}

private struct AutomaticRequestKey: Hashable {
    var accountScope: CloudAccountScope
    var generation: UInt64
}
