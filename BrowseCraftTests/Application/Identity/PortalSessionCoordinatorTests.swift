import Foundation
import Testing
@testable import BrowseCraft

struct PortalSessionCoordinatorTests {
    private static let now: Date = Date(timeIntervalSince1970: 1_785_000_000)

    @Test func missingSessionStaysSignedOutWithoutAutomaticRegistration() async {
        let userID: UUID = UUID()
        let store: InMemoryPortalSessionStore = InMemoryPortalSessionStore()
        let authenticator: MockPortalIdentityAuthenticator =
            MockPortalIdentityAuthenticator()
        let coordinator: PortalSessionCoordinator = Self.coordinator(
            userID: userID,
            store: store,
            authenticator: authenticator
        )

        await coordinator.start()

        #expect(await coordinator.snapshot().status == .signedOut)
        #expect(await authenticator.appleAuthenticationCallCount == 0)
        #expect(store.session == nil)
    }

    @Test func validStoredSessionDoesNotRefreshAtStartup() async {
        let userID: UUID = UUID()
        let credentials: PortalAuthenticationTokens = Self.tokens(
            userID: userID,
            accessToken: "access",
            refreshToken: "refresh",
            accessExpiresAt: Self.now.addingTimeInterval(601)
        )
        let store: InMemoryPortalSessionStore = InMemoryPortalSessionStore(
            session: PortalSessionPersistence(
                userID: userID,
                credentials: credentials
            )
        )
        let authenticator: MockPortalIdentityAuthenticator =
            MockPortalIdentityAuthenticator()
        let coordinator: PortalSessionCoordinator = Self.coordinator(
            userID: userID,
            store: store,
            authenticator: authenticator
        )

        await coordinator.start()

        #expect(await coordinator.snapshot().status == .authenticated)
        #expect(await authenticator.refreshCallCount == 0)
        #expect(await coordinator.validAccessToken() == "access")
    }

    @Test func expiringAccessTokenRotatesAndPersistsSession() async {
        let userID: UUID = UUID()
        let oldCredentials: PortalAuthenticationTokens = Self.tokens(
            userID: userID,
            accessToken: "old-access",
            refreshToken: "old-refresh",
            accessExpiresAt: Self.now.addingTimeInterval(60)
        )
        let newCredentials: PortalAuthenticationTokens = Self.tokens(
            userID: userID,
            accessToken: "new-access",
            refreshToken: "new-refresh",
            accessExpiresAt: Self.now.addingTimeInterval(86_400)
        )
        let store: InMemoryPortalSessionStore = InMemoryPortalSessionStore(
            session: PortalSessionPersistence(
                userID: userID,
                credentials: oldCredentials
            )
        )
        let authenticator: MockPortalIdentityAuthenticator =
            MockPortalIdentityAuthenticator(
                refreshResult: .success(newCredentials)
            )
        let coordinator: PortalSessionCoordinator = Self.coordinator(
            userID: userID,
            store: store,
            authenticator: authenticator
        )

        await coordinator.start()

        #expect(store.session?.credentials == newCredentials)
        #expect(await coordinator.validAccessToken() == "new-access")
        #expect(await authenticator.receivedRefreshTokens == ["old-refresh"])
    }

    @Test func rejectedRefreshClearsLegacySession() async {
        let userID: UUID = UUID()
        let credentials: PortalAuthenticationTokens = Self.tokens(
            userID: userID,
            accessToken: "expired",
            refreshToken: "rejected",
            accessExpiresAt: Self.now.addingTimeInterval(-1)
        )
        let store: InMemoryPortalSessionStore = InMemoryPortalSessionStore(
            session: PortalSessionPersistence(
                userID: userID,
                credentials: credentials
            )
        )
        let authenticator: MockPortalIdentityAuthenticator =
            MockPortalIdentityAuthenticator(
                refreshResult: .failure(
                    PortalIdentityAuthenticationError.refreshRejected
                )
            )
        let coordinator: PortalSessionCoordinator = Self.coordinator(
            userID: userID,
            store: store,
            authenticator: authenticator
        )

        await coordinator.start()

        #expect(store.session == nil)
        #expect(store.clearCallCount == 1)
        #expect(await coordinator.snapshot().status == .signedOut)
    }

    @Test func appleCredentialsArePersistedOnlyAfterExplicitInstallation() async throws {
        let userID: UUID = UUID()
        let credentials: PortalAuthenticationTokens = Self.tokens(
            userID: userID,
            accessToken: "apple-access",
            refreshToken: "apple-refresh",
            accessExpiresAt: Self.now.addingTimeInterval(3_600)
        )
        let store: InMemoryPortalSessionStore = InMemoryPortalSessionStore()
        let authenticator: MockPortalIdentityAuthenticator =
            MockPortalIdentityAuthenticator(
                appleAuthenticationResult: .success(credentials)
            )
        let coordinator: PortalSessionCoordinator = Self.coordinator(
            userID: userID,
            store: store,
            authenticator: authenticator
        )

        let challenge: PortalAppleAuthenticationChallenge =
            try await coordinator.issueAppleChallenge()
        let exchanged: PortalAuthenticationTokens =
            try await coordinator.authenticateWithApple(
                identityToken: "identity-token",
                nonce: challenge.nonce
            ).tokens
        #expect(store.session == nil)

        try await coordinator.installAuthenticatedSession(exchanged)

        #expect(store.session?.credentials == credentials)
        #expect(await coordinator.authenticatedUserID() == userID)
    }

    @Test func storedSessionForDifferentActiveUserIsBlocked() async {
        let activeUserID: UUID = UUID()
        let storedUserID: UUID = UUID()
        let store: InMemoryPortalSessionStore = InMemoryPortalSessionStore(
            session: PortalSessionPersistence(
                userID: storedUserID,
                credentials: Self.tokens(
                    userID: storedUserID,
                    accessToken: "other-access",
                    refreshToken: "other-refresh",
                    accessExpiresAt: Self.now.addingTimeInterval(3_600)
                )
            )
        )
        let coordinator: PortalSessionCoordinator = Self.coordinator(
            userID: activeUserID,
            store: store,
            authenticator: MockPortalIdentityAuthenticator()
        )

        await coordinator.start()

        #expect(await coordinator.snapshot().status == .accountConflict)
        #expect(await coordinator.validAccessToken() == nil)
    }

    // MARK: - 401 后强制刷新（删除账号设计第 7.1 节）

    @Test(arguments: [
        (PortalIdentityAuthenticationError.refreshRejected, PortalAuthorizationRejectionOutcome.signedOut, true),
        (PortalIdentityAuthenticationError.temporarilyUnavailable, PortalAuthorizationRejectionOutcome.unchanged, false)
    ])
    func authorizationRejectionForcesRefreshEvenWhenTokenLooksValid(
        refreshError: PortalIdentityAuthenticationError,
        expected: PortalAuthorizationRejectionOutcome,
        expectsCleared: Bool
    ) async {
        let userID: UUID = UUID()
        let credentials: PortalAuthenticationTokens = Self.tokens(
            userID: userID,
            accessToken: "access",
            refreshToken: "refresh",
            accessExpiresAt: Self.now.addingTimeInterval(3_600)
        )
        let store: InMemoryPortalSessionStore = InMemoryPortalSessionStore(
            session: PortalSessionPersistence(userID: userID, credentials: credentials)
        )
        let authenticator: MockPortalIdentityAuthenticator = MockPortalIdentityAuthenticator(
            refreshResult: .failure(refreshError)
        )
        let coordinator: PortalSessionCoordinator = Self.coordinator(
            userID: userID,
            store: store,
            authenticator: authenticator
        )
        await coordinator.start()
        #expect(await authenticator.refreshCallCount == 0)

        let outcome: PortalAuthorizationRejectionOutcome = await coordinator.handleAuthorizationRejected()

        #expect(outcome == expected)
        #expect(await authenticator.refreshCallCount == 1)
        #expect((store.session == nil) == expectsCleared)
    }

    @Test func authorizationRejectionWithSuccessfulRefreshRotatesToken() async {
        let userID: UUID = UUID()
        let store: InMemoryPortalSessionStore = InMemoryPortalSessionStore(
            session: PortalSessionPersistence(
                userID: userID,
                credentials: Self.tokens(
                    userID: userID,
                    accessToken: "old-access",
                    refreshToken: "old-refresh",
                    accessExpiresAt: Self.now.addingTimeInterval(3_600)
                )
            )
        )
        let authenticator: MockPortalIdentityAuthenticator = MockPortalIdentityAuthenticator(
            refreshResult: .success(
                Self.tokens(
                    userID: userID,
                    accessToken: "new-access",
                    refreshToken: "new-refresh",
                    accessExpiresAt: Self.now.addingTimeInterval(3_600)
                )
            )
        )
        let coordinator: PortalSessionCoordinator = Self.coordinator(
            userID: userID,
            store: store,
            authenticator: authenticator
        )
        await coordinator.start()

        #expect(await coordinator.handleAuthorizationRejected() == .refreshed)
        #expect(await coordinator.validAccessToken() == "new-access")
    }

    @Test func authorizationRejectionWithoutSessionIsNoOp() async {
        let coordinator: PortalSessionCoordinator = Self.coordinator(
            userID: UUID(),
            store: InMemoryPortalSessionStore(),
            authenticator: MockPortalIdentityAuthenticator()
        )
        await coordinator.start()

        #expect(await coordinator.handleAuthorizationRejected() == .unchanged)
    }

    /// 中文注释：服务端 2026-10-21 起把「已轮换的 refresh token 再次使用」判为重放并撤销整条链（含赢家刚拿到的新 token），
    /// 因此 App 侧对同一个 refresh token 只能发一次刷新请求。启动、回前台、网络恢复、取 access token、401 后强制刷新
    /// 五条路都汇到 `refreshIfNeeded`，靠 actor 与 `operationInFlight` 跨挂起点串行；这里钉住：刷新挂着时再来的调用
    /// 不发第二个请求、也不等它，拿仍然有效的旧 access token 走。
    @Test func concurrentRefreshesSendOneRequestWithTheSameRefreshToken() async {
        let userID: UUID = UUID()
        let oldCredentials: PortalAuthenticationTokens = Self.tokens(
            userID: userID,
            accessToken: "old-access",
            refreshToken: "old-refresh",
            accessExpiresAt: Self.now.addingTimeInterval(60)
        )
        let newCredentials: PortalAuthenticationTokens = Self.tokens(
            userID: userID,
            accessToken: "new-access",
            refreshToken: "new-refresh",
            accessExpiresAt: Self.now.addingTimeInterval(86_400)
        )
        let store: InMemoryPortalSessionStore = InMemoryPortalSessionStore(
            session: PortalSessionPersistence(userID: userID, credentials: oldCredentials)
        )
        let authenticator: MockPortalIdentityAuthenticator = MockPortalIdentityAuthenticator(
            refreshResult: .success(newCredentials)
        )
        await authenticator.holdRefreshes()
        let coordinator: PortalSessionCoordinator = Self.coordinator(
            userID: userID,
            store: store,
            authenticator: authenticator
        )

        async let first: String? = coordinator.validAccessToken()
        var attempts: Int = 0
        while await authenticator.refreshCallCount == 0, attempts < 2_000 {
            attempts += 1
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(await authenticator.refreshCallCount == 1)

        // 刷新挂着：再取 token、回前台、401 强制刷新都不得再发请求。
        let second: String? = await coordinator.validAccessToken()
        await coordinator.handleAppBecameActive()
        let rejection: PortalAuthorizationRejectionOutcome = await coordinator.handleAuthorizationRejected()
        #expect(second == "old-access")
        #expect(rejection != .refreshed)
        #expect(await authenticator.refreshCallCount == 1)

        await authenticator.releaseHeldRefreshes()
        let firstToken: String? = await first
        #expect(firstToken == "new-access")
        #expect(await authenticator.refreshCallCount == 1)
        #expect(await authenticator.receivedRefreshTokens == ["old-refresh"])
        #expect(store.session?.credentials == newCredentials)
        #expect(await coordinator.validAccessToken() == "new-access")
    }

    private static func coordinator(
        userID: UUID,
        store: InMemoryPortalSessionStore,
        authenticator: MockPortalIdentityAuthenticator
    ) -> PortalSessionCoordinator {
        return PortalSessionCoordinator(
            activeAppUser: ActiveAppUserStore(initialUserID: userID),
            sessionStore: store,
            authenticator: authenticator,
            now: { Self.now }
        )
    }

    private static func tokens(
        userID: UUID,
        accessToken: String,
        refreshToken: String,
        accessExpiresAt: Date
    ) -> PortalAuthenticationTokens {
        return PortalAuthenticationTokens(
            userID: userID,
            accessToken: accessToken,
            refreshToken: refreshToken,
            accessTokenExpiresAt: accessExpiresAt,
            refreshTokenExpiresAt: Self.now.addingTimeInterval(86_400)
        )
    }
}

private final class InMemoryPortalSessionStore:
    PortalSessionStoring,
    @unchecked Sendable {
    private(set) var session: PortalSessionPersistence?
    private(set) var clearCallCount: Int = 0

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
        self.clearCallCount += 1
        self.session = nil
    }
}

private actor MockPortalIdentityAuthenticator: PortalIdentityAuthenticating {
    private let challengeResult: Result<
        PortalAppleAuthenticationChallenge,
        any Error
    >
    private let appleAuthenticationResult: Result<
        PortalAuthenticationTokens,
        any Error
    >
    private let refreshResult: Result<PortalAuthenticationTokens, any Error>

    private(set) var appleAuthenticationCallCount: Int = 0
    private(set) var refreshCallCount: Int = 0
    private(set) var receivedRefreshTokens: [String] = []
    private var holdsRefreshes: Bool = false
    private var heldRefreshContinuations: [CheckedContinuation<Void, Never>] = []

    init(
        challengeResult: Result<
            PortalAppleAuthenticationChallenge,
            any Error
        > = .success(
            PortalAppleAuthenticationChallenge(
                nonce: "challenge-nonce",
                expiresAt: Date.distantFuture
            )
        ),
        appleAuthenticationResult: Result<
            PortalAuthenticationTokens,
            any Error
        > = .failure(PortalIdentityAuthenticationError.appleIdentityRejected),
        refreshResult: Result<
            PortalAuthenticationTokens,
            any Error
        > = .failure(PortalIdentityAuthenticationError.temporarilyUnavailable)
    ) {
        self.challengeResult = challengeResult
        self.appleAuthenticationResult = appleAuthenticationResult
        self.refreshResult = refreshResult
    }

    func issueAppleChallenge() async throws -> PortalAppleAuthenticationChallenge {
        return try self.challengeResult.get()
    }

    func authenticateWithApple(
        identityToken: String,
        nonce: String
    ) async throws -> PortalAppleAuthentication {
        _ = identityToken
        _ = nonce
        self.appleAuthenticationCallCount += 1
        return PortalAppleAuthentication(tokens: try self.appleAuthenticationResult.get())
    }

    /// 中文注释：之后的 `refresh` 在计数之后挂起，直到 `releaseHeldRefreshes()`——用来制造「刷新在途」的窗口。
    func holdRefreshes() {
        self.holdsRefreshes = true
    }

    func releaseHeldRefreshes() {
        let continuations: [CheckedContinuation<Void, Never>] = self.heldRefreshContinuations
        self.heldRefreshContinuations = []
        self.holdsRefreshes = false
        for continuation: CheckedContinuation<Void, Never> in continuations {
            continuation.resume()
        }
    }

    func refresh(refreshToken: String) async throws -> PortalAuthenticationTokens {
        self.refreshCallCount += 1
        self.receivedRefreshTokens.append(refreshToken)
        if self.holdsRefreshes {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                self.heldRefreshContinuations.append(continuation)
            }
        }
        return try self.refreshResult.get()
    }

    func logout(refreshToken: String, accessToken: String) async throws {
        _ = refreshToken
        _ = accessToken
    }

    func logoutAll(accessToken: String) async throws {
        _ = accessToken
    }
}
