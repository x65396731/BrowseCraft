import Foundation
import Testing
@testable import BrowseCraft

struct PushDeviceRegistrationCoordinatorTests {
    private static let now: Date = Date(timeIntervalSince1970: 1_785_000_000)
    private static let deviceToken: String = String(repeating: "ab", count: 32)

    @Test func tokenWithoutSessionIsNotRegistered() async {
        let registrar: SpyPushDeviceRegistrar = SpyPushDeviceRegistrar()
        let coordinator: PushDeviceRegistrationCoordinator = Self.coordinator(
            registrar: registrar,
            userID: UUID(),
            session: nil
        )

        await coordinator.updateDeviceToken(Self.deviceToken)
        await coordinator.synchronizeRegistration()

        #expect(await registrar.registrations.isEmpty)
    }

    @Test func tokenWithValidSessionRegistersExactlyOnce() async {
        let userID: UUID = UUID()
        let registrar: SpyPushDeviceRegistrar = SpyPushDeviceRegistrar()
        let coordinator: PushDeviceRegistrationCoordinator = Self.coordinator(
            registrar: registrar,
            userID: userID,
            session: Self.session(userID: userID)
        )

        await coordinator.updateDeviceToken(Self.deviceToken)
        await coordinator.synchronizeRegistration()
        await coordinator.updateDeviceToken(Self.deviceToken)

        let registrations: [SpyPushDeviceRegistrar.Call] = await registrar.registrations
        #expect(registrations.count == 1)
        #expect(
            registrations.first == SpyPushDeviceRegistrar.Call(
                deviceToken: Self.deviceToken,
                environment: .sandbox,
                accessToken: "access"
            )
        )
    }

    @Test func failedRegistrationIsRetriedOnNextSynchronize() async {
        let userID: UUID = UUID()
        let registrar: SpyPushDeviceRegistrar = SpyPushDeviceRegistrar(
            registerResults: [.failure(PushDeviceRegistrationError.transport), .success(())]
        )
        let coordinator: PushDeviceRegistrationCoordinator = Self.coordinator(
            registrar: registrar,
            userID: userID,
            session: Self.session(userID: userID)
        )

        await coordinator.updateDeviceToken(Self.deviceToken)
        await coordinator.synchronizeRegistration()
        await coordinator.synchronizeRegistration()

        #expect(await registrar.registrations.count == 2)
    }

    @Test func unregisterUsesSessionTokenAndAllowsReregistration() async {
        let userID: UUID = UUID()
        let registrar: SpyPushDeviceRegistrar = SpyPushDeviceRegistrar()
        let coordinator: PushDeviceRegistrationCoordinator = Self.coordinator(
            registrar: registrar,
            userID: userID,
            session: Self.session(userID: userID)
        )

        await coordinator.updateDeviceToken(Self.deviceToken)
        await coordinator.unregisterCurrentDevice()
        await coordinator.synchronizeRegistration()

        let unregistrations: [SpyPushDeviceRegistrar.Call] = await registrar.unregistrations
        #expect(unregistrations.count == 1)
        #expect(unregistrations.first?.accessToken == "access")
        #expect(await registrar.registrations.count == 2)
    }

    @Test func unregisterWithoutTokenDoesNothing() async {
        let userID: UUID = UUID()
        let registrar: SpyPushDeviceRegistrar = SpyPushDeviceRegistrar()
        let coordinator: PushDeviceRegistrationCoordinator = Self.coordinator(
            registrar: registrar,
            userID: userID,
            session: Self.session(userID: userID)
        )

        await coordinator.unregisterCurrentDevice()

        #expect(await registrar.unregistrations.isEmpty)
    }

    private static func coordinator(
        registrar: SpyPushDeviceRegistrar,
        userID: UUID,
        session: PortalSessionPersistence?
    ) -> PushDeviceRegistrationCoordinator {
        let sessionCoordinator: PortalSessionCoordinator = PortalSessionCoordinator(
            activeAppUser: ActiveAppUserStore(initialUserID: userID),
            sessionStore: InMemoryPortalSessionStore(session: session),
            authenticator: StubPortalIdentityAuthenticator(),
            now: { Self.now }
        )
        return PushDeviceRegistrationCoordinator(
            environment: .sandbox,
            registrar: registrar,
            sessionCoordinator: sessionCoordinator
        )
    }

    private static func session(userID: UUID) -> PortalSessionPersistence {
        return PortalSessionPersistence(
            userID: userID,
            credentials: PortalAuthenticationTokens(
                userID: userID,
                accessToken: "access",
                refreshToken: "refresh",
                accessTokenExpiresAt: Self.now.addingTimeInterval(3_600),
                refreshTokenExpiresAt: Self.now.addingTimeInterval(86_400)
            )
        )
    }
}

private actor SpyPushDeviceRegistrar: PushDeviceRegistering {
    struct Call: Equatable, Sendable {
        let deviceToken: String
        let environment: PushEnvironment
        let accessToken: String
    }

    private var registerResults: [Result<Void, any Error>]
    private(set) var registrations: [Call] = []
    private(set) var unregistrations: [Call] = []

    init(registerResults: [Result<Void, any Error>] = []) {
        self.registerResults = registerResults
    }

    func register(
        deviceToken: String,
        environment: PushEnvironment,
        accessToken: String
    ) async throws {
        self.registrations.append(
            Call(deviceToken: deviceToken, environment: environment, accessToken: accessToken)
        )
        guard self.registerResults.isEmpty == false else {
            return
        }
        try self.registerResults.removeFirst().get()
    }

    func unregister(
        deviceToken: String,
        environment: PushEnvironment,
        accessToken: String
    ) async throws {
        self.unregistrations.append(
            Call(deviceToken: deviceToken, environment: environment, accessToken: accessToken)
        )
    }
}

private final class InMemoryPortalSessionStore: PortalSessionStoring, @unchecked Sendable {
    private var session: PortalSessionPersistence?

    init(session: PortalSessionPersistence?) {
        self.session = session
    }

    func load() throws -> PortalSessionPersistence? {
        return self.session
    }

    func save(_ session: PortalSessionPersistence) throws {
        self.session = session
    }

    func clear() throws {
        self.session = nil
    }
}

/// 中文注释：推送协调器只读会话，不触发任何认证往返；所有认证方法都不应被调用。
private struct StubPortalIdentityAuthenticator: PortalIdentityAuthenticating {
    func issueAppleChallenge() async throws -> PortalAppleAuthenticationChallenge {
        throw PortalIdentityAuthenticationError.temporarilyUnavailable
    }

    func authenticateWithApple(
        identityToken: String,
        nonce: String
    ) async throws -> PortalAuthenticationTokens {
        throw PortalIdentityAuthenticationError.temporarilyUnavailable
    }

    func refresh(refreshToken: String) async throws -> PortalAuthenticationTokens {
        throw PortalIdentityAuthenticationError.temporarilyUnavailable
    }

    func logout(refreshToken: String, accessToken: String) async throws {}

    func logoutAll(accessToken: String) async throws {}
}
