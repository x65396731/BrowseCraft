import Foundation

/// 中文注释：统一串行化 register/refresh，并把所有模糊结果收敛为可恢复或明确阻断的状态。
actor PortalSessionCoordinator {
    private let activeAppUser: any ActiveAppUserProviding
    private let sessionStore: any PortalSessionStoring
    private let authenticator: any PortalIdentityAuthenticating
    private let networkMonitor: (any PortalNetworkAvailabilityMonitoring)?
    private let refreshLeeway: TimeInterval
    private let now: @Sendable () -> Date

    private var persistedSession: PortalSessionPersistence?
    private var currentSnapshot: PortalSessionSnapshot
    private var hasLoadedSession: Bool = false
    private var operationInFlight: Bool = false
    private var networkMonitoringTask: Task<Void, Never>?

    deinit {
        self.networkMonitoringTask?.cancel()
    }

    init(
        activeAppUser: any ActiveAppUserProviding,
        sessionStore: any PortalSessionStoring,
        authenticator: any PortalIdentityAuthenticating,
        networkMonitor: (any PortalNetworkAvailabilityMonitoring)? = nil,
        refreshLeeway: TimeInterval = 5 * 60,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        let userID: UUID = activeAppUser.currentUserID
        self.activeAppUser = activeAppUser
        self.sessionStore = sessionStore
        self.authenticator = authenticator
        self.networkMonitor = networkMonitor
        self.refreshLeeway = refreshLeeway
        self.now = now
        self.currentSnapshot = PortalSessionSnapshot(
            status: .notRegistered,
            userID: userID,
            accessTokenExpiresAt: nil,
            refreshTokenExpiresAt: nil
        )
    }

    func start() async {
        self.startNetworkMonitoringIfNeeded()
        guard self.hasLoadedSession == false else {
            await self.reconcile(allowRegistrationRetry: false)
            return
        }

        let activeUserID: UUID = self.activeAppUser.currentUserID
        do {
            let storedSession: PortalSessionPersistence? = try self.sessionStore.load()
            self.hasLoadedSession = true

            guard let storedSession else {
                self.persistedSession = PortalSessionPersistence(userID: activeUserID)
                await self.reconcile(allowRegistrationRetry: true)
                return
            }
            guard storedSession.userID == activeUserID else {
                self.persistedSession = storedSession
                self.publish(status: .accountConflict)
                return
            }

            self.persistedSession = storedSession
            await self.reconcile(allowRegistrationRetry: true)
        } catch {
            self.hasLoadedSession = true
            self.publish(status: .recoveryRequired)
        }
    }

    func handleAppBecameActive() async {
        guard self.hasLoadedSession else {
            await self.start()
            return
        }
        await self.reconcile(allowRegistrationRetry: true)
    }

    func snapshot() -> PortalSessionSnapshot {
        return self.currentSnapshot
    }

    /// 中文注释：后续受保护 API 只能通过此入口取 Token，避免绕过过期和轮换判断。
    func validAccessToken() async -> String? {
        if self.hasLoadedSession == false {
            await self.start()
        } else {
            await self.refreshIfNeeded()
        }

        guard let session: PortalSessionPersistence = self.persistedSession,
              let credentials: PortalAuthenticationTokens = session.credentials,
              session.userID == self.activeAppUser.currentUserID,
              credentials.userID == session.userID,
              credentials.accessToken.isEmpty == false,
              credentials.accessTokenExpiresAt > self.now() else {
            return nil
        }
        return credentials.accessToken
    }

    private func reconcile(allowRegistrationRetry: Bool) async {
        guard self.operationInFlight == false,
              let session: PortalSessionPersistence = self.persistedSession else {
            return
        }
        guard session.userID == self.activeAppUser.currentUserID else {
            self.publish(status: .accountConflict)
            return
        }

        if let credentials: PortalAuthenticationTokens = session.credentials {
            guard credentials.userID == session.userID else {
                self.publish(status: .accountConflict)
                return
            }
            await self.refreshIfNeeded()
            return
        }

        switch session.registrationState {
        case .neverAttempted:
            await self.register()
        case .attempting, .outcomeUnknown:
            if allowRegistrationRetry {
                await self.register()
            } else {
                self.publish(status: .registrationOutcomeUnknown)
            }
        case .authenticated, .recoveryRequired:
            self.publish(status: .recoveryRequired)
        case .accountConflict:
            self.publish(status: .accountConflict)
        }
    }

    private func register() async {
        guard self.operationInFlight == false,
              var session: PortalSessionPersistence = self.persistedSession else {
            return
        }

        self.operationInFlight = true
        defer {
            self.operationInFlight = false
        }

        session.registrationState = .attempting
        if session.registrationAttemptID == nil {
            session.registrationAttemptID = UUID()
        }
        guard self.persist(session, failureStatus: .recoveryRequired) else {
            return
        }
        self.publish(status: .registering)

        do {
            let credentials: PortalAuthenticationTokens = try await self.authenticator.register(
                userID: session.userID
            )
            guard credentials.userID == session.userID,
                  credentials.userID == self.activeAppUser.currentUserID else {
                session.registrationState = .accountConflict
                session.credentials = nil
                _ = self.persist(session, failureStatus: .accountConflict)
                self.publish(status: .accountConflict)
                return
            }
            guard self.credentialsAreUsable(credentials) else {
                session.registrationState = .recoveryRequired
                session.credentials = nil
                _ = self.persist(session, failureStatus: .recoveryRequired)
                self.publish(status: .recoveryRequired)
                return
            }

            session.registrationState = .authenticated
            session.credentials = credentials
            guard self.persist(session, failureStatus: .recoveryRequired) else {
                return
            }
            self.publish(status: .authenticated)
        } catch is CancellationError {
            session.registrationState = .outcomeUnknown
            _ = self.persist(session, failureStatus: .registrationOutcomeUnknown)
            self.publish(status: .registrationOutcomeUnknown)
        } catch let error as PortalIdentityAuthenticationError {
            self.handleRegistration(error: error, session: session)
        } catch {
            session.registrationState = .outcomeUnknown
            _ = self.persist(session, failureStatus: .registrationOutcomeUnknown)
            self.publish(status: .registrationOutcomeUnknown)
        }
    }

    private func refreshIfNeeded() async {
        guard self.operationInFlight == false,
              var session: PortalSessionPersistence = self.persistedSession,
              let credentials: PortalAuthenticationTokens = session.credentials else {
            return
        }
        guard session.userID == self.activeAppUser.currentUserID,
              credentials.userID == session.userID else {
            self.publish(status: .accountConflict)
            return
        }

        let currentDate: Date = self.now()
        guard credentials.accessToken.isEmpty == false,
              credentials.refreshToken.isEmpty == false else {
            session.registrationState = .recoveryRequired
            _ = self.persist(session, failureStatus: .recoveryRequired)
            self.publish(status: .recoveryRequired)
            return
        }
        guard credentials.refreshTokenExpiresAt > currentDate else {
            session.registrationState = .recoveryRequired
            _ = self.persist(session, failureStatus: .recoveryRequired)
            self.publish(status: .recoveryRequired)
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
                  refreshed.userID == self.activeAppUser.currentUserID else {
                session.registrationState = .accountConflict
                _ = self.persist(session, failureStatus: .accountConflict)
                self.publish(status: .accountConflict)
                return
            }
            guard self.credentialsAreUsable(refreshed) else {
                session.registrationState = .recoveryRequired
                _ = self.persist(session, failureStatus: .recoveryRequired)
                self.publish(status: .recoveryRequired)
                return
            }

            session.registrationState = .authenticated
            session.credentials = refreshed
            guard self.persist(session, failureStatus: .recoveryRequired) else {
                return
            }
            self.publish(status: .authenticated)
        } catch is CancellationError {
            self.publish(
                status: credentials.accessTokenExpiresAt > self.now()
                    ? .authenticated
                    : .temporarilyUnavailable
            )
        } catch let error as PortalIdentityAuthenticationError {
            self.handleRefresh(error: error, session: session)
        } catch {
            self.publish(status: .temporarilyUnavailable)
        }
    }

    private func handleRegistration(
        error: PortalIdentityAuthenticationError,
        session originalSession: PortalSessionPersistence
    ) {
        var session: PortalSessionPersistence = originalSession

        switch error {
        case .temporarilyUnavailable, .responseOutcomeUnknown:
            session.registrationState = .outcomeUnknown
            _ = self.persist(session, failureStatus: .registrationOutcomeUnknown)
            self.publish(status: .registrationOutcomeUnknown)
        case .subjectMismatch:
            session.registrationState = .accountConflict
            _ = self.persist(session, failureStatus: .accountConflict)
            self.publish(status: .accountConflict)
        case .registrationAlreadyExists, .refreshRejected, .contractRejected,
             .clientConfiguration:
            session.registrationState = .recoveryRequired
            _ = self.persist(session, failureStatus: .recoveryRequired)
            self.publish(status: .recoveryRequired)
        }
    }

    private func handleRefresh(
        error: PortalIdentityAuthenticationError,
        session originalSession: PortalSessionPersistence
    ) {
        var session: PortalSessionPersistence = originalSession

        switch error {
        case .temporarilyUnavailable:
            self.publish(status: .temporarilyUnavailable)
        case .subjectMismatch:
            session.registrationState = .accountConflict
            _ = self.persist(session, failureStatus: .accountConflict)
            self.publish(status: .accountConflict)
        case .registrationAlreadyExists, .refreshRejected, .responseOutcomeUnknown,
             .contractRejected, .clientConfiguration:
            session.registrationState = .recoveryRequired
            _ = self.persist(session, failureStatus: .recoveryRequired)
            self.publish(status: .recoveryRequired)
        }
    }

    @discardableResult
    private func persist(
        _ session: PortalSessionPersistence,
        failureStatus: PortalSessionStatus
    ) -> Bool {
        do {
            try self.sessionStore.save(session)
            self.persistedSession = session
            return true
        } catch {
            self.publish(status: failureStatus)
            return false
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
        await self.reconcile(allowRegistrationRetry: true)
    }
}
