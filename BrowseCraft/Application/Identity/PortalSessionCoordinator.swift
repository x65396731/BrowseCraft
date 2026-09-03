import Foundation
import OSLog

enum PortalSessionInstallationError: Error, Equatable, Sendable {
    case activeUserMismatch
    case credentialsInvalid
    case operationInFlight
    case invalidTransition
}

/// 中文注释：Portal Session 只接受后端签发的 AppUser UUID，不再生成 UUID 或自动注册。
actor PortalSessionCoordinator {
    private let activeAppUser: any ActiveAppUserProviding
    private let sessionStore: any PortalSessionStoring
    private let authenticator: any PortalIdentityAuthenticating
    private let networkMonitor: (any PortalNetworkAvailabilityMonitoring)?
    private let identityOriginStore: (any PortalAppUserIdentityOriginStoring)?
    private let entitlementCacheResetter: (any PortalEntitlementCacheResetting)?
    private let refreshLeeway: TimeInterval
    private let now: @Sendable () -> Date

    private var persistedSession: PortalSessionPersistence?
    private var currentSnapshot: PortalSessionSnapshot
    private var hasLoadedSession: Bool = false
    private var operationInFlight: Bool = false
    private var pendingIdentityTransition: PendingIdentityTransition?
    private var networkMonitoringTask: Task<Void, Never>?

    private struct PendingIdentityTransition: Sendable {
        let id: UUID
        let stagedSession: PortalSessionPersistence
        let previousSession: PortalSessionPersistence?
        let previousSnapshot: PortalSessionSnapshot
    }

    deinit {
        self.networkMonitoringTask?.cancel()
    }

    init(
        activeAppUser: any ActiveAppUserProviding,
        sessionStore: any PortalSessionStoring,
        authenticator: any PortalIdentityAuthenticating,
        networkMonitor: (any PortalNetworkAvailabilityMonitoring)? = nil,
        identityOriginStore: (any PortalAppUserIdentityOriginStoring)? = nil,
        entitlementCacheResetter: (any PortalEntitlementCacheResetting)? = nil,
        refreshLeeway: TimeInterval = 5 * 60,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        let userID: UUID = activeAppUser.currentUserID
        self.activeAppUser = activeAppUser
        self.sessionStore = sessionStore
        self.authenticator = authenticator
        self.networkMonitor = networkMonitor
        self.identityOriginStore = identityOriginStore
        self.entitlementCacheResetter = entitlementCacheResetter
        self.refreshLeeway = refreshLeeway
        self.now = now
        self.currentSnapshot = PortalSessionSnapshot(
            status: .signedOut,
            userID: userID,
            accessTokenExpiresAt: nil,
            refreshTokenExpiresAt: nil
        )
    }

    func start() async {
        self.startNetworkMonitoringIfNeeded()
        guard self.hasLoadedSession == false else {
            await self.refreshIfNeeded()
            return
        }

        do {
            let storedSession: PortalSessionPersistence? = try self.sessionStore.load()
            self.hasLoadedSession = true
            guard let storedSession else {
                try? self.entitlementCacheResetter?.resetPortalEntitlements(
                    for: self.activeAppUser.currentUserID
                )
                self.publish(status: .signedOut)
                return
            }
            guard Self.sessionIsInternallyConsistent(storedSession),
                  storedSession.userID == self.activeAppUser.currentUserID else {
                self.persistedSession = storedSession
                try? self.clearLocalSession()
                self.publish(status: .accountConflict)
                try? await self.authenticator.logout(
                    refreshToken: storedSession.credentials.refreshToken,
                    accessToken: storedSession.credentials.accessToken
                )
                return
            }

            self.persistedSession = storedSession
            try? self.identityOriginStore?.markPortalUserID(storedSession.userID)
            await self.refreshIfNeeded()
        } catch {
            self.hasLoadedSession = true
            self.persistedSession = nil
            try? self.entitlementCacheResetter?.resetPortalEntitlements(
                for: self.activeAppUser.currentUserID
            )
            PortalSessionDiagnostics.error(
                "event=session-load result=failed action=require-apple-sign-in"
            )
            self.publish(status: .signedOut)
        }
    }

    func handleAppBecameActive() async {
        guard self.hasLoadedSession else {
            await self.start()
            return
        }
        await self.refreshIfNeeded()
    }

    func snapshot() -> PortalSessionSnapshot {
        return self.currentSnapshot
    }

    func issueAppleChallenge() async throws -> PortalAppleAuthenticationChallenge {
        guard self.operationInFlight == false else {
            throw PortalSessionInstallationError.operationInFlight
        }
        return try await self.authenticator.issueAppleChallenge()
    }

    /// 中文注释：只交换 Apple 凭证，不切换本地数据 owner；调用方确认账户迁移后再安装 Session。
    func authenticateWithApple(
        identityToken: String,
        nonce: String
    ) async throws -> PortalAuthenticationTokens {
        guard self.operationInFlight == false else {
            throw PortalSessionInstallationError.operationInFlight
        }

        let previousStatus: PortalSessionStatus = self.currentSnapshot.status
        self.operationInFlight = true
        self.publish(status: .authenticating)
        defer {
            self.operationInFlight = false
        }

        do {
            let credentials: PortalAuthenticationTokens = try await self.authenticator
                .authenticateWithApple(
                    identityToken: identityToken,
                    nonce: nonce
                )
            guard self.credentialsAreUsable(credentials) else {
                self.publish(status: previousStatus)
                throw PortalSessionInstallationError.credentialsInvalid
            }
            return credentials
        } catch let error as PortalIdentityAuthenticationError {
            self.publish(
                status: error == .userDisabled
                    ? .userDisabled
                    : previousStatus
            )
            throw error
        } catch {
            self.publish(status: previousStatus)
            throw error
        }
    }

    func installAuthenticatedSession(
        _ credentials: PortalAuthenticationTokens
    ) throws {
        guard self.activeAppUser.currentUserID == credentials.userID else {
            throw PortalSessionInstallationError.activeUserMismatch
        }
        guard self.operationInFlight == false else {
            throw PortalSessionInstallationError.operationInFlight
        }
        guard self.credentialsAreUsable(credentials) else {
            throw PortalSessionInstallationError.credentialsInvalid
        }

        let session: PortalSessionPersistence = PortalSessionPersistence(
            userID: credentials.userID,
            credentials: credentials
        )
        try self.sessionStore.save(session)
        self.persistedSession = session
        self.hasLoadedSession = true
        self.publish(status: .authenticated)
    }

    /// 中文注释：先把目标账户 Session 写入 Keychain，身份切换完成后只需无 I/O 提交。
    func stageAuthenticatedSessionTransition(
        _ credentials: PortalAuthenticationTokens,
        from sourceUserID: UUID
    ) throws -> UUID {
        guard self.activeAppUser.currentUserID == sourceUserID,
              credentials.userID != sourceUserID else {
            throw PortalSessionInstallationError.activeUserMismatch
        }
        guard self.operationInFlight == false else {
            throw PortalSessionInstallationError.operationInFlight
        }
        guard self.credentialsAreUsable(credentials) else {
            throw PortalSessionInstallationError.credentialsInvalid
        }

        let stagedSession: PortalSessionPersistence = PortalSessionPersistence(
            userID: credentials.userID,
            credentials: credentials
        )
        try self.sessionStore.save(stagedSession)
        let transition: PendingIdentityTransition = PendingIdentityTransition(
            id: UUID(),
            stagedSession: stagedSession,
            previousSession: self.persistedSession,
            previousSnapshot: self.currentSnapshot
        )
        self.pendingIdentityTransition = transition
        self.operationInFlight = true
        return transition.id
    }

    /// 中文注释：账户 UUID 已切换后，提交只更新 actor 内存，不再留下 Keychain 失败窗口。
    func commitAuthenticatedSessionTransition(_ transitionID: UUID) throws {
        guard let transition: PendingIdentityTransition = self.pendingIdentityTransition,
              transition.id == transitionID,
              self.activeAppUser.currentUserID == transition.stagedSession.userID else {
            throw PortalSessionInstallationError.invalidTransition
        }
        self.persistedSession = transition.stagedSession
        self.hasLoadedSession = true
        self.pendingIdentityTransition = nil
        self.operationInFlight = false
        self.publish(status: .authenticated)
    }

    /// 中文注释：身份切换失败时先恢复旧 Keychain，再尽力注销已签发但未采用的新 Session。
    func rollbackAuthenticatedSessionTransition(_ transitionID: UUID) async {
        guard let transition: PendingIdentityTransition = self.pendingIdentityTransition,
              transition.id == transitionID else {
            return
        }

        do {
            if let previousSession: PortalSessionPersistence = transition.previousSession {
                try self.sessionStore.save(previousSession)
            } else {
                try self.sessionStore.clear()
            }
            self.persistedSession = transition.previousSession
            self.currentSnapshot = transition.previousSnapshot
        } catch {
            try? self.sessionStore.clear()
            self.persistedSession = nil
            self.publish(status: .signedOut)
        }
        self.hasLoadedSession = true
        self.pendingIdentityTransition = nil
        self.operationInFlight = false

        try? await self.authenticator.logout(
            refreshToken: transition.stagedSession.credentials.refreshToken,
            accessToken: transition.stagedSession.credentials.accessToken
        )
    }

    /// 中文注释：交换成功但本地未采用的凭据不得在服务端长期留存。
    func discardUninstalledCredentials(
        _ credentials: PortalAuthenticationTokens
    ) async {
        try? await self.authenticator.logout(
            refreshToken: credentials.refreshToken,
            accessToken: credentials.accessToken
        )
    }

    func validAccessToken() async -> String? {
        if self.hasLoadedSession == false {
            await self.start()
        } else {
            await self.refreshIfNeeded()
        }

        guard let session: PortalSessionPersistence = self.persistedSession,
              Self.sessionIsInternallyConsistent(session),
              session.userID == self.activeAppUser.currentUserID,
              session.credentials.accessToken.isEmpty == false,
              session.credentials.accessTokenExpiresAt > self.now() else {
            return nil
        }
        return session.credentials.accessToken
    }

    func authenticatedUserID() async -> UUID? {
        guard await self.validAccessToken() != nil,
              let session: PortalSessionPersistence = self.persistedSession else {
            return nil
        }
        return session.userID
    }

    func logout() async throws {
        guard self.operationInFlight == false else {
            throw PortalSessionInstallationError.operationInFlight
        }
        guard let session: PortalSessionPersistence = self.persistedSession else {
            try self.clearLocalSession()
            return
        }

        self.operationInFlight = true
        defer {
            self.operationInFlight = false
        }
        do {
            try await self.authenticator.logout(
                refreshToken: session.credentials.refreshToken,
                accessToken: session.credentials.accessToken
            )
        } catch {
            PortalSessionDiagnostics.error(
                "event=logout remote-revoke=failed action=clear-local-session"
            )
        }
        try self.clearLocalSession()
    }

    func logoutAll() async throws {
        guard self.operationInFlight == false else {
            throw PortalSessionInstallationError.operationInFlight
        }
        guard let session: PortalSessionPersistence = self.persistedSession else {
            try self.clearLocalSession()
            return
        }

        self.operationInFlight = true
        defer {
            self.operationInFlight = false
        }
        let remoteError: (any Error)?
        do {
            try await self.authenticator.logoutAll(
                accessToken: session.credentials.accessToken
            )
            remoteError = nil
        } catch {
            remoteError = error
        }
        try self.clearLocalSession()
        if let remoteError {
            throw remoteError
        }
    }

    private func refreshIfNeeded() async {
        guard self.operationInFlight == false,
              var session: PortalSessionPersistence = self.persistedSession else {
            return
        }
        guard Self.sessionIsInternallyConsistent(session),
              session.userID == self.activeAppUser.currentUserID else {
            try? self.clearLocalSession()
            self.publish(status: .accountConflict)
            try? await self.authenticator.logout(
                refreshToken: session.credentials.refreshToken,
                accessToken: session.credentials.accessToken
            )
            return
        }

        let credentials: PortalAuthenticationTokens = session.credentials
        let currentDate: Date = self.now()
        guard credentials.refreshTokenExpiresAt > currentDate else {
            try? self.clearLocalSession()
            return
        }
        guard credentials.accessTokenExpiresAt <=
                currentDate.addingTimeInterval(self.refreshLeeway) else {
            self.publish(status: .authenticated)
            return
        }

        self.operationInFlight = true
        defer {
            self.operationInFlight = false
        }

        do {
            let refreshed: PortalAuthenticationTokens = try await self.authenticator.refresh(
                refreshToken: credentials.refreshToken
            )
            guard refreshed.userID == session.userID,
                  refreshed.userID == self.activeAppUser.currentUserID,
                  self.credentialsAreUsable(refreshed) else {
                try? self.clearLocalSession()
                self.publish(status: .accountConflict)
                try? await self.authenticator.logout(
                    refreshToken: refreshed.refreshToken,
                    accessToken: refreshed.accessToken
                )
                return
            }

            session.credentials = refreshed
            try self.sessionStore.save(session)
            self.persistedSession = session
            self.publish(status: .authenticated)
        } catch is CancellationError {
            self.publish(
                status: credentials.accessTokenExpiresAt > self.now()
                    ? .authenticated
                    : .temporarilyUnavailable
            )
        } catch let error as PortalIdentityAuthenticationError {
            switch error {
            case .refreshRejected:
                try? self.clearLocalSession()
            case .userDisabled:
                try? self.clearLocalSession()
                self.publish(status: .userDisabled)
            case .temporarilyUnavailable, .responseOutcomeUnknown:
                self.publish(status: .temporarilyUnavailable)
            case .appleChallengeRejected, .appleIdentityRejected,
                 .contractRejected, .clientConfiguration:
                self.publish(status: .temporarilyUnavailable)
            }
        } catch {
            self.publish(status: .temporarilyUnavailable)
        }
    }

    private func clearLocalSession() throws {
        let userID: UUID = self.activeAppUser.currentUserID
        var firstError: (any Error)?
        do {
            try self.sessionStore.clear()
        } catch {
            firstError = error
        }
        do {
            try self.entitlementCacheResetter?.resetPortalEntitlements(
                for: userID
            )
        } catch {
            if firstError == nil {
                firstError = error
            }
        }
        self.persistedSession = nil
        self.hasLoadedSession = true
        self.publish(status: .signedOut)
        if let firstError {
            throw firstError
        }
    }

    private func publish(status: PortalSessionStatus) {
        let credentials: PortalAuthenticationTokens? = self.persistedSession?.credentials
        self.currentSnapshot = PortalSessionSnapshot(
            status: status,
            userID: self.activeAppUser.currentUserID,
            accessTokenExpiresAt: credentials?.accessTokenExpiresAt,
            refreshTokenExpiresAt: credentials?.refreshTokenExpiresAt
        )
    }

    private func credentialsAreUsable(_ credentials: PortalAuthenticationTokens) -> Bool {
        let currentDate: Date = self.now()
        return credentials.accessToken.isEmpty == false &&
            credentials.refreshToken.isEmpty == false &&
            credentials.accessTokenExpiresAt > currentDate &&
            credentials.refreshTokenExpiresAt > currentDate
    }

    private static func sessionIsInternallyConsistent(
        _ session: PortalSessionPersistence
    ) -> Bool {
        return session.schemaVersion == PortalSessionPersistence.currentSchemaVersion &&
            session.userID == session.credentials.userID
    }

    private func startNetworkMonitoringIfNeeded() {
        guard self.networkMonitoringTask == nil,
              let networkMonitor: any PortalNetworkAvailabilityMonitoring =
                self.networkMonitor else {
            return
        }

        let updates: AsyncStream<Bool> = networkMonitor.statusUpdates()
        self.networkMonitoringTask = Task { [weak self] in
            var previousAvailability: Bool?
            for await isAvailable: Bool in updates {
                guard Task.isCancelled == false else {
                    return
                }
                if previousAvailability == false, isAvailable {
                    await self?.handleNetworkBecameAvailable()
                }
                previousAvailability = isAvailable
            }
        }
    }

    private func handleNetworkBecameAvailable() async {
        guard self.hasLoadedSession else {
            await self.start()
            return
        }
        await self.refreshIfNeeded()
    }
}

enum PortalSessionDiagnostics {
    private static let logger: Logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "BrowseCraft",
        category: "PortalSession"
    )

    static func notice(_ message: String) {
        Self.logger.notice("[BrowseCraftPortalSession] \(message, privacy: .public)")
    }

    static func error(_ message: String) {
        Self.logger.error("[BrowseCraftPortalSession] \(message, privacy: .public)")
    }
}

/// 中文注释：任务提交只借用已存在的 `validAccessToken()`，不新增凭据通道（`BC-PREFLIGHT-045`）。
extension PortalSessionCoordinator: PortalAccessTokenProviding {}
