import CloudKit
import Foundation

/// 中文注释：CloudKitAccountStateService 是账户状态层唯一直接依赖 CloudKit 的实现。
actor CloudKitAccountStateService: CloudAccountStateProviding {
    private let containerIdentifier: String
    private let container: CKContainer
    private let notificationCenter: NotificationCenter
    private let scopeDeriver: CloudAccountScopeDeriver

    private var state: CloudAccountState = .initial
    private var lastKnownCloudScope: CloudAccountScope?
    private var accountChangedObserver: NSObjectProtocol?
    private var continuations: [UUID: AsyncStream<CloudAccountState>.Continuation] = [:]

    init(
        containerIdentifier: String,
        notificationCenter: NotificationCenter = .default,
        scopeDeriver: CloudAccountScopeDeriver = CloudAccountScopeDeriver()
    ) {
        self.containerIdentifier = containerIdentifier
        self.container = CKContainer(identifier: containerIdentifier)
        self.notificationCenter = notificationCenter
        self.scopeDeriver = scopeDeriver
    }

    func currentState() async -> CloudAccountState {
        return self.state
    }

    func stateUpdates() async -> AsyncStream<CloudAccountState> {
        let id: UUID = UUID()
        return AsyncStream { continuation in
            self.continuations[id] = continuation
            continuation.yield(self.state)
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeContinuation(id: id)
                }
            }
        }
    }

    func startMonitoring() async {
        if self.accountChangedObserver == nil {
            self.accountChangedObserver = self.notificationCenter.addObserver(
                forName: .CKAccountChanged,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                Task {
                    await self?.refresh()
                }
            }
        }

        await self.refresh()
    }

    func stopMonitoring() async {
        guard let observer: NSObjectProtocol = self.accountChangedObserver else {
            return
        }
        self.notificationCenter.removeObserver(observer)
        self.accountChangedObserver = nil
    }

    func refresh() async {
        do {
            let accountStatus: CKAccountStatus = try await self.loadAccountStatus()
            await self.resolve(accountStatus)
        } catch {
            self.updateState(
                CloudAccountState(
                    availability: .couldNotDetermine,
                    scope: self.lastKnownCloudScope ?? .localDefault
                )
            )
        }
    }

    private func resolve(_ accountStatus: CKAccountStatus) async {
        switch accountStatus {
        case .available:
            do {
                let recordID: CKRecord.ID = try await self.loadUserRecordID()
                let scope: CloudAccountScope = self.scopeDeriver.derive(
                    containerIdentifier: self.containerIdentifier,
                    userRecordName: recordID.recordName
                )
                self.lastKnownCloudScope = scope
                self.updateState(
                    CloudAccountState(availability: .available, scope: scope)
                )
            } catch {
                self.updateState(
                    CloudAccountState(
                        availability: .couldNotDetermine,
                        scope: self.lastKnownCloudScope ?? .localDefault
                    )
                )
            }

        case .noAccount:
            self.lastKnownCloudScope = nil
            self.updateState(
                CloudAccountState(availability: .noAccount, scope: .localDefault)
            )

        case .restricted:
            self.lastKnownCloudScope = nil
            self.updateState(
                CloudAccountState(availability: .restricted, scope: .localDefault)
            )

        case .temporarilyUnavailable:
            self.updateState(
                CloudAccountState(
                    availability: .temporarilyUnavailable,
                    scope: self.lastKnownCloudScope ?? .localDefault
                )
            )

        case .couldNotDetermine:
            self.updateState(
                CloudAccountState(
                    availability: .couldNotDetermine,
                    scope: self.lastKnownCloudScope ?? .localDefault
                )
            )

        @unknown default:
            self.updateState(
                CloudAccountState(
                    availability: .couldNotDetermine,
                    scope: self.lastKnownCloudScope ?? .localDefault
                )
            )
        }
    }

    private func loadAccountStatus() async throws -> CKAccountStatus {
        return try await withCheckedThrowingContinuation { continuation in
            self.container.accountStatus { status, error in
                if let error: Error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }

    private func loadUserRecordID() async throws -> CKRecord.ID {
        return try await withCheckedThrowingContinuation { continuation in
            self.container.fetchUserRecordID { recordID, error in
                if let error: Error = error {
                    continuation.resume(throwing: error)
                } else if let recordID: CKRecord.ID = recordID {
                    continuation.resume(returning: recordID)
                } else {
                    continuation.resume(throwing: CloudKitAccountStateServiceError.missingUserRecordID)
                }
            }
        }
    }

    private func updateState(_ newState: CloudAccountState) {
        guard self.state != newState else {
            return
        }

        self.state = newState
        for continuation: AsyncStream<CloudAccountState>.Continuation in self.continuations.values {
            continuation.yield(newState)
        }
    }

    private func removeContinuation(id: UUID) {
        self.continuations.removeValue(forKey: id)
    }
}

private enum CloudKitAccountStateServiceError: Error {
    case missingUserRecordID
}
