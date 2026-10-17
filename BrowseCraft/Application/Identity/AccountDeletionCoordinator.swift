import BrowseCraftLog
import Foundation

/// 中文注释：删号失败的成因（docs/design/Account-Deletion-Design.md 第八节）。除 `outcomeUnknown` 外都表示「账号未删除」。
enum AccountDeletionError: Error, Equatable, Sendable {
    case operationInFlight
    case reauthenticationCancelled
    case reauthenticationFailed
    case sessionExpired
    case verificationExpired
    case appleAccountMismatch
    case appleUnavailable
    case notConfigured
    case persistenceFailed
    case rateLimited
    case network
    /// 中文注释：请求发出后没拿到可判读的响应、当场也探不出结果；标记留着，启动与回到前台时再确认。
    case outcomeUnknown
    case failed
}

/// 中文注释：服务端已删除之后的收尾情况，完成页按它附说明。
struct AccountDeletionOutcome: Equatable, Sendable {
    enum LocalCleanup: Equatable, Sendable {
        case done
        /// 中文注释：下次启动或回到前台时自动重试。
        case pending
        /// 中文注释：连续失败到第三次，请用户删除并重新安装 App。
        case reinstallRequired
    }

    enum CloudCleanup: Equatable, Sendable {
        case done
        /// 中文注释：iCloud 暂时连不上或本 App 的 iCloud 被关，连上后自动清除。
        case pending
    }

    let appleRevocationFailed: Bool
    let localCleanup: LocalCleanup
    let cloudCleanup: CloudCleanup
}

/// 中文注释：删除账号的完整流程与收尾（docs/design/Account-Deletion-Design.md 第四–七节）：
/// 重新验证 Apple → 服务端删除 → 先换访客身份、再删旧 UUID 的本机数据 → 清 iCloud；中途没做完的靠持久化标记续做。
@MainActor
final class AccountDeletionCoordinator {
    static let reinstallThreshold: Int = 3

    private let activeAppUser: ActiveAppUserStore
    private let session: any AccountDeletionSessionControlling
    private let appleAuthorizer: any AppleSignInAuthorizing
    private let deletionService: any PortalAccountDeleting
    private let guestProvisioner: any GuestIdentityProvisioning
    private let localDataStore: any AccountDeletionLocalDataStoring
    private let bookFileStore: (any BookFileStoring)?
    private let cloudEraser: any AccountDeletionCloudDataErasing
    private let pendingWorkStore: any AccountDeletionPendingWorkStoring
    private let appleUserIdentifierStore: (any AppleUserIdentifierStoring)?
    private let prepareForIdentityChange: @MainActor () async -> Void
    private let didResetIdentity: @MainActor () async -> Void
    private var isRunning: Bool = false

    init(
        activeAppUser: ActiveAppUserStore,
        session: any AccountDeletionSessionControlling,
        appleAuthorizer: any AppleSignInAuthorizing,
        deletionService: any PortalAccountDeleting,
        guestProvisioner: any GuestIdentityProvisioning,
        localDataStore: any AccountDeletionLocalDataStoring,
        bookFileStore: (any BookFileStoring)?,
        cloudEraser: any AccountDeletionCloudDataErasing,
        pendingWorkStore: any AccountDeletionPendingWorkStoring,
        appleUserIdentifierStore: (any AppleUserIdentifierStoring)?,
        prepareForIdentityChange: @escaping @MainActor () async -> Void,
        didResetIdentity: @escaping @MainActor () async -> Void
    ) {
        self.activeAppUser = activeAppUser
        self.session = session
        self.appleAuthorizer = appleAuthorizer
        self.deletionService = deletionService
        self.guestProvisioner = guestProvisioner
        self.localDataStore = localDataStore
        self.bookFileStore = bookFileStore
        self.cloudEraser = cloudEraser
        self.pendingWorkStore = pendingWorkStore
        self.appleUserIdentifierStore = appleUserIdentifierStore
        self.prepareForIdentityChange = prepareForIdentityChange
        self.didResetIdentity = didResetIdentity
    }

    // MARK: - 删除流程（第四节）

    func deleteAccount() async throws -> AccountDeletionOutcome {
        guard self.isRunning == false else {
            throw AccountDeletionError.operationInFlight
        }
        self.isRunning = true
        defer {
            self.isRunning = false
        }

        let userID: UUID = self.activeAppUser.currentUserID
        guard await self.session.validAccessToken() != nil else {
            throw AccountDeletionError.sessionExpired
        }

        let challenge: PortalAppleAuthenticationChallenge
        do {
            challenge = try await self.session.issueAppleChallenge()
        } catch let error as PortalIdentityAuthenticationError
            where error == .temporarilyUnavailable || error == .responseOutcomeUnknown {
            throw AccountDeletionError.network
        } catch {
            throw AccountDeletionError.failed
        }

        let authorization: AppleSignInAuthorization
        do {
            authorization = try await self.appleAuthorizer.authorize(nonce: challenge.nonce)
        } catch let error as AppleSignInAuthorizationError where error == .cancelled {
            throw AccountDeletionError.reauthenticationCancelled
        } catch {
            throw AccountDeletionError.reauthenticationFailed
        }

        // 中文注释：用户在 Apple 界面里停留期间令牌可能临近过期，发请求前再取一次（会按需刷新）。
        guard self.activeAppUser.currentUserID == userID,
              let accessToken: String = await self.session.validAccessToken() else {
            throw AccountDeletionError.sessionExpired
        }

        self.updatePendingWork { work in
            work.inFlightUserID = userID
        }
        AppLog.notice(.identity, "account-deletion-request-start")
        let result: AccountDeletionServerResult
        do {
            result = try await self.deletionService.deleteAccount(
                accessToken: accessToken,
                identityToken: authorization.identityToken,
                nonce: challenge.nonce,
                authorizationCode: authorization.authorizationCode
            )
        } catch AccountDeletionServiceError.outcomeUnknown {
            // 中文注释：服务端可能已经删了；当场探一次，探不出就把标记留给下次启动。
            switch await self.deletionService.probeAccount(accessToken: accessToken) {
            case .deleted:
                AppLog.notice(.identity, "account-deletion-confirmed-by-probe")
                return await self.completeDeletion(userID: userID, appleRevocationFailed: false)
            case .exists:
                self.updatePendingWork { work in
                    work.inFlightUserID = nil
                }
                throw AccountDeletionError.network
            case .unknown:
                throw AccountDeletionError.outcomeUnknown
            }
        } catch {
            self.updatePendingWork { work in
                work.inFlightUserID = nil
            }
            AppLog.error(.identity, "account-deletion-request-failed", [
                "reason": .code("\(Self.safeCode(error))")
            ])
            throw Self.map(error)
        }

        AppLog.notice(.identity, "account-deletion-request-succeeded", [
            "appleRevocationFailed": .bool(result.appleRevocationFailed)
        ])
        return await self.completeDeletion(
            userID: userID,
            appleRevocationFailed: result.appleRevocationFailed
        )
    }

    // MARK: - 续做（第七节）

    /// 中文注释：启动、回到前台、网络恢复时调用；没有待办时只读一次 UserDefaults。
    func resumePendingWork() async {
        guard self.isRunning == false,
              self.pendingWorkStore.load().isEmpty == false else {
            return
        }
        self.isRunning = true
        defer {
            self.isRunning = false
        }

        if let inFlightUserID: UUID = self.pendingWorkStore.load().inFlightUserID {
            switch await self.probeInFlightDeletion(userID: inFlightUserID) {
            case .deleted:
                AppLog.notice(.identity, "account-deletion-resume-in-flight", ["outcome": .code("deleted")])
                _ = await self.completeDeletion(userID: inFlightUserID, appleRevocationFailed: false)
                return
            case .exists:
                AppLog.notice(.identity, "account-deletion-resume-in-flight", ["outcome": .code("exists")])
                self.updatePendingWork { work in
                    work.inFlightUserID = nil
                }
            case .unknown:
                return
            }
        }

        for userID: UUID in self.pendingWorkStore.load().localCleanupUserIDs {
            _ = await self.runLocalCleanup(userID: userID)
        }
        for cleanup: AccountDeletionPendingWork.CloudCleanup in self.pendingWorkStore.load().cloudCleanups {
            _ = await self.runCloudCleanup(cleanup)
        }
    }

    private func probeInFlightDeletion(userID: UUID) async -> AccountDeletionProbeResult {
        guard self.activeAppUser.currentUserID == userID else {
            return .unknown
        }
        if let accessToken: String = await self.session.validAccessToken() {
            return await self.deletionService.probeAccount(accessToken: accessToken)
        }
        // 中文注释：取不到令牌时看会话为什么没了：刷新被服务端拒绝会落到 signedOut（账号已删，会话随之级联删除）；
        // 暂时不可用说明只是连不上，下次再判。
        switch await self.session.snapshot().status {
        case .signedOut, .userDisabled, .accountConflict:
            return .deleted
        case .authenticating, .authenticated, .temporarilyUnavailable:
            return .unknown
        }
    }

    // MARK: - 收尾（第五、六节）

    private func completeDeletion(
        userID: UUID,
        appleRevocationFailed: Bool
    ) async -> AccountDeletionOutcome {
        let associatedScopes: [CloudAccountScope] =
            (try? self.localDataStore.associatedCloudScopes(for: userID)) ?? []
        self.updatePendingWork { work in
            work.inFlightUserID = nil
            if work.localCleanupUserIDs.contains(userID) == false {
                work.localCleanupUserIDs.append(userID)
            }
            if work.cloudCleanups.contains(where: { $0.userID == userID }) == false {
                work.cloudCleanups.append(
                    AccountDeletionPendingWork.CloudCleanup(
                        userID: userID,
                        associatedScopes: associatedScopes
                    )
                )
            }
        }

        await self.prepareForIdentityChange()
        await self.session.discardLocalSessionForDeletedAccount()
        do {
            try self.appleUserIdentifierStore?.clearUserIdentifier()
        } catch {
            AppLog.error(.identity, "account-deletion-apple-user-identifier-clear-failed")
        }

        let localCleanup: AccountDeletionOutcome.LocalCleanup = await self.runLocalCleanup(userID: userID)
        let cloudCleanup: AccountDeletionOutcome.CloudCleanup
        if let pending: AccountDeletionPendingWork.CloudCleanup = self.pendingWorkStore.load()
            .cloudCleanups.first(where: { $0.userID == userID }) {
            cloudCleanup = await self.runCloudCleanup(pending)
        } else {
            cloudCleanup = .done
        }
        return AccountDeletionOutcome(
            appleRevocationFailed: appleRevocationFailed,
            localCleanup: localCleanup,
            cloudCleanup: cloudCleanup
        )
    }

    /// 中文注释：先换访客身份、再删旧 UUID 的行——旧用户被删时它已经不是活动用户，任何仓储都不会再为它读写。
    private func runLocalCleanup(userID: UUID) async -> AccountDeletionOutcome.LocalCleanup {
        do {
            if self.activeAppUser.currentUserID == userID {
                let guestUserID: UUID = try self.guestProvisioner.provisionNewGuest()
                self.activeAppUser.update(guestUserID)
                AppLog.notice(.identity, "account-deletion-identity-reset-to-guest")
                await self.session.discardLocalSessionForDeletedAccount()
                await self.didResetIdentity()
            }
            let bookFilePaths: [String] = try self.localDataStore.deleteLocalData(for: userID)
            self.updatePendingWork { work in
                work.localCleanupUserIDs.removeAll { $0 == userID }
                work.localCleanupFailureCount = 0
            }
            // 中文注释：文件删除失败不回滚：书已不在书架，残留文件只占空间（与 DeleteLocalBookUseCase 同一取舍）。
            for relativePath: String in bookFilePaths {
                try? await self.bookFileStore?.removeFile(relativePath: relativePath)
            }
            AppLog.notice(.identity, "account-deletion-local-cleanup-completed", [
                "bookFileCount": .int(bookFilePaths.count)
            ])
            // 中文注释：本机日志随账号一起删（Logging-Design.md BCA-OBS-016）；之后的记录写进新文件。
            AppLogging.removeLocalLogFiles()
            return .done
        } catch {
            var failureCount: Int = 0
            self.updatePendingWork { work in
                work.localCleanupFailureCount += 1
                failureCount = work.localCleanupFailureCount
            }
            AppLog.error(.identity, "account-deletion-local-cleanup-failed", [
                "attempt": .int(failureCount),
                "reason": .code("\(Self.safeCode(error))")
            ])
            return failureCount >= Self.reinstallThreshold ? .reinstallRequired : .pending
        }
    }

    private func runCloudCleanup(
        _ cleanup: AccountDeletionPendingWork.CloudCleanup
    ) async -> AccountDeletionOutcome.CloudCleanup {
        do {
            let erasure: AccountDeletionCloudErasure = try await self.cloudEraser.eraseCloudData(
                for: cleanup.userID,
                associatedScopes: cleanup.associatedScopes
            )
            self.updatePendingWork { work in
                work.cloudCleanups.removeAll { $0.userID == cleanup.userID }
            }
            AppLog.notice(.identity, "account-deletion-cloud-cleanup-completed", [
                "result": .code("\(erasure == .erased ? "erased" : "not-owned")")
            ])
            return .done
        } catch {
            AppLog.notice(.identity, "account-deletion-cloud-cleanup-deferred", [
                "reason": .code("\(Self.safeCode(error))")
            ])
            return .pending
        }
    }

    // MARK: - 工具

    private func updatePendingWork(_ change: (inout AccountDeletionPendingWork) -> Void) {
        var work: AccountDeletionPendingWork = self.pendingWorkStore.load()
        change(&work)
        self.pendingWorkStore.save(work)
    }

    private static func map(_ error: any Error) -> AccountDeletionError {
        guard let serviceError: AccountDeletionServiceError = error as? AccountDeletionServiceError else {
            return error is CancellationError ? .network : .failed
        }
        switch serviceError {
        case .sessionExpired:
            return .sessionExpired
        case .verificationExpired:
            return .verificationExpired
        case .appleAccountMismatch:
            return .appleAccountMismatch
        case .appleUnavailable:
            return .appleUnavailable
        case .notConfigured:
            return .notConfigured
        case .persistenceFailed:
            return .persistenceFailed
        case .rateLimited:
            return .rateLimited
        case .outcomeUnknown:
            return .outcomeUnknown
        case .rejected:
            return .failed
        }
    }

    private static func safeCode(_ error: any Error) -> String {
        if let serviceError: AccountDeletionServiceError = error as? AccountDeletionServiceError {
            if case .rejected(let code) = serviceError {
                return "rejected-\(code)"
            }
            return String(describing: serviceError)
        }
        if let erasureError: AccountDeletionCloudErasureError = error as? AccountDeletionCloudErasureError {
            return String(describing: erasureError)
        }
        if let diagnosable: any DiagnosticSummaryProviding = error as? any DiagnosticSummaryProviding {
            return diagnosable.diagnosticSummary
        }
        return String(reflecting: type(of: error))
    }
}
