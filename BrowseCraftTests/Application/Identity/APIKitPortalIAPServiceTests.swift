import Foundation
import Testing
@testable import BrowseCraft

struct APIKitPortalIAPServiceTests {
    @Test func purchaseRefreshUsesAuthenticatedPortalUserAndAccessToken() async throws {
        let userID: UUID = UUID()
        let context: PortalIAPTestContext = PortalIAPTestContext(userID: userID)
        let snapshot: PortalEntitlementSnapshot = try await context.coordinator
            .refreshPurchasedEntitlements(
                userID: userID,
                environment: .sandbox,
                signedTransaction: "signed-transaction"
            )

        #expect(snapshot.userID == userID)
        #expect(await context.iapService.lastUserID == userID)
        #expect(await context.iapService.lastAccessToken == "access-token")
        #expect(await context.iapService.lastSignedTransactions == ["signed-transaction"])
    }

    @Test func restoreRequiresExistingPortalSessionAndNeverRecoversFromPurchaseProof() async {
        let userID: UUID = UUID()
        let activeUser: ActiveAppUserStore = ActiveAppUserStore(
            initialUserID: userID
        )
        let sessionCoordinator: PortalSessionCoordinator = PortalSessionCoordinator(
            activeAppUser: activeUser,
            sessionStore: PortalIAPTestSessionStore(),
            authenticator: PortalIAPTestIdentityAuthenticator()
        )
        let coordinator: PortalPurchaseEntitlementRefreshCoordinator =
            PortalPurchaseEntitlementRefreshCoordinator(
                activeAppUser: activeUser,
                portalSessionCoordinator: sessionCoordinator,
                portalIAPService: PortalIAPTestService(userID: userID)
            )

        do {
            _ = try await coordinator.restoreEntitlements(
                userID: userID,
                environment: .sandbox,
                signedTransactions: ["signed-transaction"]
            )
            Issue.record("Expected restore to require Sign in with Apple.")
        } catch let error as PortalPurchaseEntitlementRefreshError {
            #expect(error == .sessionUnavailable)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

private struct PortalIAPTestContext {
    let coordinator: PortalPurchaseEntitlementRefreshCoordinator
    let iapService: PortalIAPTestService

    init(userID: UUID) {
        let activeUser: ActiveAppUserStore = ActiveAppUserStore(
            initialUserID: userID
        )
        let credentials: PortalAuthenticationTokens = PortalAuthenticationTokens(
            userID: userID,
            accessToken: "access-token",
            refreshToken: "refresh-token",
            accessTokenExpiresAt: Date().addingTimeInterval(3_600),
            refreshTokenExpiresAt: Date().addingTimeInterval(86_400)
        )
        let sessionStore: PortalIAPTestSessionStore = PortalIAPTestSessionStore(
            session: PortalSessionPersistence(
                userID: userID,
                credentials: credentials
            )
        )
        let sessionCoordinator: PortalSessionCoordinator = PortalSessionCoordinator(
            activeAppUser: activeUser,
            sessionStore: sessionStore,
            authenticator: PortalIAPTestIdentityAuthenticator(
                refreshResult: .success(credentials)
            )
        )
        let service: PortalIAPTestService = PortalIAPTestService(userID: userID)
        self.iapService = service
        self.coordinator = PortalPurchaseEntitlementRefreshCoordinator(
            activeAppUser: activeUser,
            portalSessionCoordinator: sessionCoordinator,
            portalIAPService: service
        )
    }
}

private actor PortalIAPTestService: PortalIAPServicing {
    private let userID: UUID
    private(set) var lastUserID: UUID?
    private(set) var lastAccessToken: String?
    private(set) var lastSignedTransactions: [String] = []

    init(userID: UUID) {
        self.userID = userID
    }

    func refreshEntitlements(
        userID: UUID,
        environment: PortalPurchaseEnvironment,
        signedTransactions: [String],
        accessToken: String
    ) async throws -> PortalEntitlementSnapshot {
        self.lastUserID = userID
        self.lastAccessToken = accessToken
        self.lastSignedTransactions = signedTransactions
        return PortalEntitlementSnapshot(
            userID: self.userID,
            environment: environment,
            includedSiteSlots: 1,
            purchasedSiteSlots: 0,
            siteSlotLimit: 1,
            hasRemovedAds: false,
            activeProductIDs: [],
            revision: 0,
            verifiedAt: Date()
        )
    }
}

private final class PortalIAPTestSessionStore:
    PortalSessionStoring,
    @unchecked Sendable {
    private var session: PortalSessionPersistence?

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
        self.session = nil
    }
}

private actor PortalIAPTestIdentityAuthenticator: PortalIdentityAuthenticating {
    private let refreshResult: Result<PortalAuthenticationTokens, any Error>

    init(
        refreshResult: Result<PortalAuthenticationTokens, any Error> =
            .failure(PortalIdentityAuthenticationError.refreshRejected)
    ) {
        self.refreshResult = refreshResult
    }

    func issueAppleChallenge() async throws -> PortalAppleAuthenticationChallenge {
        throw PortalIdentityAuthenticationError.temporarilyUnavailable
    }

    func authenticateWithApple(
        identityToken: String,
        nonce: String
    ) async throws -> PortalAuthenticationTokens {
        _ = identityToken
        _ = nonce
        throw PortalIdentityAuthenticationError.appleIdentityRejected
    }

    func refresh(refreshToken: String) async throws -> PortalAuthenticationTokens {
        _ = refreshToken
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
