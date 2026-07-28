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
            )
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
    ) async throws -> PortalAuthenticationTokens {
        _ = identityToken
        _ = nonce
        self.appleAuthenticationCallCount += 1
        return try self.appleAuthenticationResult.get()
    }

    func refresh(refreshToken: String) async throws -> PortalAuthenticationTokens {
        self.refreshCallCount += 1
        self.receivedRefreshTokens.append(refreshToken)
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
