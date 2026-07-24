import Foundation
import Testing
@testable import BrowseCraft

struct PortalSessionCoordinatorTests {
    private static let now: Date = Date(timeIntervalSince1970: 1_785_000_000)

    @Test func newIdentityRegistersAndPersistsTokens() async throws {
        let userID: UUID = try Self.userID("7125df34-6803-47ef-af12-4ae763b1b806")
        let response: PortalAuthenticationTokens = Self.tokens(
            userID: userID,
            accessToken: "access-1",
            refreshToken: "refresh-1",
            accessExpiresAt: Self.now.addingTimeInterval(3_600)
        )
        let store: InMemoryPortalSessionStore = InMemoryPortalSessionStore()
        let authenticator: MockPortalIdentityAuthenticator =
            MockPortalIdentityAuthenticator(registerResult: .success(response))
        let coordinator: PortalSessionCoordinator = Self.coordinator(
            userID: userID,
            store: store,
            authenticator: authenticator
        )

        await coordinator.start()

        let snapshot: PortalSessionSnapshot = await coordinator.snapshot()
        let registerCallCount: Int = await authenticator.registerCallCount
        #expect(snapshot.status == .authenticated)
        #expect(registerCallCount == 1)
        #expect(store.session?.registrationState == .authenticated)
        #expect(store.session?.credentials == response)
        #expect(store.savedStates.first == .attempting)
        #expect(store.savedStates.last == .authenticated)
    }

    @Test func validAccessTokenDoesNotRefreshAtStartup() async throws {
        let userID: UUID = try Self.userID("1ba2eab7-8e2c-41e5-aafb-22f85794f6fe")
        let credentials: PortalAuthenticationTokens = Self.tokens(
            userID: userID,
            accessToken: "still-valid",
            refreshToken: "refresh",
            accessExpiresAt: Self.now.addingTimeInterval(601)
        )
        let store: InMemoryPortalSessionStore = InMemoryPortalSessionStore(
            session: Self.session(userID: userID, credentials: credentials)
        )
        let authenticator: MockPortalIdentityAuthenticator =
            MockPortalIdentityAuthenticator()
        let coordinator: PortalSessionCoordinator = Self.coordinator(
            userID: userID,
            store: store,
            authenticator: authenticator
        )

        await coordinator.start()

        let snapshot: PortalSessionSnapshot = await coordinator.snapshot()
        let refreshCallCount: Int = await authenticator.refreshCallCount
        #expect(snapshot.status == .authenticated)
        #expect(refreshCallCount == 0)
    }

    @Test func tokenWithinFiveMinutesIsRefreshedAndAtomicallyReplaced() async throws {
        let userID: UUID = try Self.userID("7a9bd1f5-e1a6-4b04-b36a-c952750385c5")
        let oldCredentials: PortalAuthenticationTokens = Self.tokens(
            userID: userID,
            accessToken: "old-access",
            refreshToken: "old-refresh",
            accessExpiresAt: Self.now.addingTimeInterval(300)
        )
        let newCredentials: PortalAuthenticationTokens = Self.tokens(
            userID: userID,
            accessToken: "new-access",
            refreshToken: "new-refresh",
            accessExpiresAt: Self.now.addingTimeInterval(86_400)
        )
        let store: InMemoryPortalSessionStore = InMemoryPortalSessionStore(
            session: Self.session(userID: userID, credentials: oldCredentials)
        )
        let authenticator: MockPortalIdentityAuthenticator =
            MockPortalIdentityAuthenticator(refreshResult: .success(newCredentials))
        let coordinator: PortalSessionCoordinator = Self.coordinator(
            userID: userID,
            store: store,
            authenticator: authenticator
        )

        await coordinator.start()

        let refreshTokens: [String] = await authenticator.receivedRefreshTokens
        let accessToken: String? = await coordinator.validAccessToken()
        #expect(refreshTokens == ["old-refresh"])
        #expect(store.session?.credentials == newCredentials)
        #expect(accessToken == "new-access")
    }

    @Test func temporaryRefreshFailureKeepsExistingCredentials() async throws {
        let userID: UUID = try Self.userID("632b0056-e14a-407c-bb5e-c51fb46be37e")
        let credentials: PortalAuthenticationTokens = Self.tokens(
            userID: userID,
            accessToken: "expired-access",
            refreshToken: "preserved-refresh",
            accessExpiresAt: Self.now.addingTimeInterval(-1)
        )
        let store: InMemoryPortalSessionStore = InMemoryPortalSessionStore(
            session: Self.session(userID: userID, credentials: credentials)
        )
        let authenticator: MockPortalIdentityAuthenticator = MockPortalIdentityAuthenticator(
            refreshResult: .failure(PortalIdentityAuthenticationError.temporarilyUnavailable)
        )
        let coordinator: PortalSessionCoordinator = Self.coordinator(
            userID: userID,
            store: store,
            authenticator: authenticator
        )

        await coordinator.start()

        let snapshot: PortalSessionSnapshot = await coordinator.snapshot()
        #expect(snapshot.status == .temporarilyUnavailable)
        #expect(store.session?.credentials == credentials)
        #expect(store.session?.registrationState == .authenticated)
    }

    @Test func alreadyRegisteredIdentityRequiresRecoveryAndDoesNotRetryImmediately() async throws {
        let userID: UUID = try Self.userID("7e46f2b0-0516-474c-bad6-8561999f71e4")
        let store: InMemoryPortalSessionStore = InMemoryPortalSessionStore()
        let authenticator: MockPortalIdentityAuthenticator = MockPortalIdentityAuthenticator(
            registerResult: .failure(
                PortalIdentityAuthenticationError.registrationAlreadyExists
            )
        )
        let coordinator: PortalSessionCoordinator = Self.coordinator(
            userID: userID,
            store: store,
            authenticator: authenticator
        )

        await coordinator.start()
        await coordinator.handleAppBecameActive()

        let snapshot: PortalSessionSnapshot = await coordinator.snapshot()
        let registerCallCount: Int = await authenticator.registerCallCount
        #expect(snapshot.status == .recoveryRequired)
        #expect(registerCallCount == 1)
        #expect(store.session?.registrationState == .recoveryRequired)
    }

    @Test func storedSessionForAnotherUserIsBlockedWithoutNetworkRequest() async throws {
        let activeUserID: UUID = try Self.userID("cc439366-c780-42e5-bc99-cfa2a8cabbd9")
        let storedUserID: UUID = try Self.userID("cdbb53f7-429a-4e8f-ad7f-f36d35900c04")
        let store: InMemoryPortalSessionStore = InMemoryPortalSessionStore(
            session: Self.session(
                userID: storedUserID,
                credentials: Self.tokens(
                    userID: storedUserID,
                    accessToken: "other-access",
                    refreshToken: "other-refresh",
                    accessExpiresAt: Self.now.addingTimeInterval(3_600)
                )
            )
        )
        let authenticator: MockPortalIdentityAuthenticator =
            MockPortalIdentityAuthenticator()
        let coordinator: PortalSessionCoordinator = Self.coordinator(
            userID: activeUserID,
            store: store,
            authenticator: authenticator
        )

        await coordinator.start()

        let snapshot: PortalSessionSnapshot = await coordinator.snapshot()
        let registerCallCount: Int = await authenticator.registerCallCount
        let refreshCallCount: Int = await authenticator.refreshCallCount
        #expect(snapshot.status == .accountConflict)
        #expect(registerCallCount == 0)
        #expect(refreshCallCount == 0)
    }

    @Test func credentialsForAnotherUserAreBlockedEvenWhenSessionOwnerMatches() async throws {
        let activeUserID: UUID = try Self.userID("70f4682a-eafc-4402-9610-41c81f01f9ce")
        let otherUserID: UUID = try Self.userID("68ad646e-3256-4cf3-9ab5-e5e371784777")
        let store: InMemoryPortalSessionStore = InMemoryPortalSessionStore(
            session: Self.session(
                userID: activeUserID,
                credentials: Self.tokens(
                    userID: otherUserID,
                    accessToken: "wrong-access",
                    refreshToken: "wrong-refresh",
                    accessExpiresAt: Self.now.addingTimeInterval(3_600)
                )
            )
        )
        let authenticator: MockPortalIdentityAuthenticator =
            MockPortalIdentityAuthenticator()
        let coordinator: PortalSessionCoordinator = Self.coordinator(
            userID: activeUserID,
            store: store,
            authenticator: authenticator
        )

        await coordinator.start()

        let snapshot: PortalSessionSnapshot = await coordinator.snapshot()
        let accessToken: String? = await coordinator.validAccessToken()
        #expect(snapshot.status == .accountConflict)
        #expect(accessToken == nil)
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

    private static func session(
        userID: UUID,
        credentials: PortalAuthenticationTokens
    ) -> PortalSessionPersistence {
        return PortalSessionPersistence(
            userID: userID,
            registrationState: .authenticated,
            credentials: credentials
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
            refreshTokenExpiresAt: Self.now.addingTimeInterval(180 * 24 * 60 * 60)
        )
    }

    private static func userID(_ value: String) throws -> UUID {
        return try #require(UUID(uuidString: value))
    }
}

private final class InMemoryPortalSessionStore: PortalSessionStoring, @unchecked Sendable {
    private(set) var session: PortalSessionPersistence?
    private(set) var savedStates: [PortalRegistrationState] = []

    init(session: PortalSessionPersistence? = nil) {
        self.session = session
    }

    func load() throws -> PortalSessionPersistence? {
        return self.session
    }

    func save(_ session: PortalSessionPersistence) throws {
        self.session = session
        self.savedStates.append(session.registrationState)
    }
}

private actor MockPortalIdentityAuthenticator: PortalIdentityAuthenticating {
    private let registerResult: Result<
        PortalAuthenticationTokens,
        PortalIdentityAuthenticationError
    >
    private let refreshResult: Result<
        PortalAuthenticationTokens,
        PortalIdentityAuthenticationError
    >

    private(set) var registerCallCount: Int = 0
    private(set) var refreshCallCount: Int = 0
    private(set) var receivedRefreshTokens: [String] = []

    init(
        registerResult: Result<
            PortalAuthenticationTokens,
            PortalIdentityAuthenticationError
        > = .failure(
            PortalIdentityAuthenticationError.clientConfiguration
        ),
        refreshResult: Result<
            PortalAuthenticationTokens,
            PortalIdentityAuthenticationError
        > = .failure(
            PortalIdentityAuthenticationError.clientConfiguration
        )
    ) {
        self.registerResult = registerResult
        self.refreshResult = refreshResult
    }

    func register(userID: UUID) async throws -> PortalAuthenticationTokens {
        _ = userID
        self.registerCallCount += 1
        return try self.registerResult.get()
    }

    func refresh(refreshToken: String) async throws -> PortalAuthenticationTokens {
        self.refreshCallCount += 1
        self.receivedRefreshTokens.append(refreshToken)
        return try self.refreshResult.get()
    }
}
