import BrowseCraftAPIKit
import Foundation
import StoreKit
import Testing
@testable import BrowseCraft

struct APIKitPortalIAPServiceTests {
    @Test func storeKitEnvironmentMapsOnlyAppleServerEnvironments() throws {
        #expect(
            try StoreKitPortalEnvironmentMapper.map(.sandbox) == .sandbox
        )
        #expect(
            try StoreKitPortalEnvironmentMapper.map(.production) == .production
        )
        #expect(
            throws: StoreKitPortalPurchaseSubmissionError
                .xcodeEnvironmentUnsupported
        ) {
            _ = try StoreKitPortalEnvironmentMapper.map(.xcode)
        }
    }

    @Test func purchaseRefreshUsesValidatedSessionAndSingleJWS() async throws {
        let userID: UUID = UUID()
        let activeUser: ActiveAppUserStore = ActiveAppUserStore(
            initialUserID: userID
        )
        let sessionStore: PurchaseRefreshTestSessionStore =
            PurchaseRefreshTestSessionStore(
                session: PortalSessionPersistence(
                    userID: userID,
                    registrationState: .authenticated,
                    credentials: PortalAuthenticationTokens(
                        userID: userID,
                        accessToken: "access-token",
                        refreshToken: "refresh-token",
                        accessTokenExpiresAt: Date().addingTimeInterval(3_600),
                        refreshTokenExpiresAt: Date().addingTimeInterval(86_400)
                    )
                )
            )
        let portalSessionCoordinator: PortalSessionCoordinator =
            PortalSessionCoordinator(
                activeAppUser: activeUser,
                sessionStore: sessionStore,
                authenticator: PurchaseRefreshTestAuthenticator()
            )
        let service: PurchaseRefreshTestIAPService =
            PurchaseRefreshTestIAPService(userID: userID)
        let coordinator: PortalPurchaseEntitlementRefreshCoordinator =
            PortalPurchaseEntitlementRefreshCoordinator(
                activeAppUser: activeUser,
                portalSessionCoordinator: portalSessionCoordinator,
                portalIAPService: service
            )

        let snapshot: PortalEntitlementSnapshot =
            try await coordinator.refreshPurchasedEntitlements(
                userID: userID,
                environment: .sandbox,
                signedTransaction: "signed-jws"
            )

        let request: PurchaseRefreshTestIAPService.Request? =
            await service.lastRequest
        #expect(snapshot.userID == userID)
        #expect(request?.userID == userID)
        #expect(request?.environment == .sandbox)
        #expect(request?.signedTransactions == ["signed-jws"])
        #expect(request?.accessToken == "access-token")
    }

    @Test func refreshMapsVerifiedSnapshotWithoutExposingTransportDetails() async throws {
        let userID: UUID = UUID()
        let transport: IAPServiceTestTransport = IAPServiceTestTransport(
            response: PortalAPITransportResponse(
                data: Data(
                    """
                    {
                      "userId": "\(userID.uuidString)",
                      "environment": "Sandbox",
                      "includedSiteSlots": 1,
                      "purchasedSiteSlots": 5,
                      "siteSlotLimit": 6,
                      "hasRemovedAds": true,
                      "activeProductIds": ["slot.5", "remove.ads"],
                      "revision": 4,
                      "verifiedAt": "2026-07-25T00:00:00Z"
                    }
                    """.utf8
                ),
                statusCode: 200
            )
        )
        let service: APIKitPortalIAPService = Self.makeService(
            transport: transport
        )

        let snapshot: PortalEntitlementSnapshot =
            try await service.refreshEntitlements(
                userID: userID,
                environment: .sandbox,
                signedTransactions: ["signed-jws"],
                accessToken: "access-token"
            )

        #expect(snapshot.userID == userID)
        #expect(snapshot.siteSlotLimit == 6)
        #expect(snapshot.purchasedSiteSlots == 5)
        #expect(snapshot.hasRemovedAds)
        #expect(snapshot.activeProductIDs == ["slot.5", "remove.ads"])
        #expect(snapshot.revision == 4)
    }

    @Test func restoreRecoversMissingSessionBeforeRefreshingEntitlements() async throws {
        let userID: UUID = UUID()
        let activeUser: ActiveAppUserStore = ActiveAppUserStore(
            initialUserID: userID
        )
        let sessionStore: PurchaseRefreshTestSessionStore =
            PurchaseRefreshTestSessionStore(
                session: PortalSessionPersistence(
                    userID: userID,
                    registrationState: .recoveryRequired
                )
            )
        let portalSessionCoordinator: PortalSessionCoordinator =
            PortalSessionCoordinator(
                activeAppUser: activeUser,
                sessionStore: sessionStore,
                authenticator: PurchaseRefreshTestAuthenticator()
            )
        let service: PurchaseRefreshTestIAPService =
            PurchaseRefreshTestIAPService(userID: userID)
        let coordinator: PortalPurchaseEntitlementRefreshCoordinator =
            PortalPurchaseEntitlementRefreshCoordinator(
                activeAppUser: activeUser,
                portalSessionCoordinator: portalSessionCoordinator,
                portalIAPService: service
            )

        _ = try await coordinator.restoreEntitlements(
            userID: userID,
            environment: .sandbox,
            signedTransactions: ["jws-a", "jws-b"],
            recoveryProof: "jws-a"
        )

        let recoveryProof: String? = await service.lastRecoveryProof
        let refreshRequest: PurchaseRefreshTestIAPService.Request? =
            await service.lastRequest
        #expect(recoveryProof == "jws-a")
        #expect(refreshRequest?.signedTransactions == ["jws-a", "jws-b"])
        #expect(
            try sessionStore.load()?.registrationState ==
                PortalRegistrationState.authenticated
        )
        #expect(try sessionStore.load()?.credentials?.userID == userID)
    }

    @Test func recoverMapsAlreadyClaimedTransactionToStableDomainError() async throws {
        let transport: IAPServiceTestTransport = IAPServiceTestTransport(
            response: PortalAPITransportResponse(
                data: Data(
                    """
                    {
                      "error": {
                        "code": "IAP_TRANSACTION_ALREADY_CLAIMED",
                        "message": "The transaction belongs to another app user.",
                        "requestId": "request-1",
                        "details": {}
                      }
                    }
                    """.utf8
                ),
                statusCode: 409
            )
        )
        let service: APIKitPortalIAPService = Self.makeService(
            transport: transport
        )

        do {
            _ = try await service.recoverSession(
                userID: UUID(),
                signedTransaction: "signed-jws"
            )
            Issue.record("Expected the transaction owner conflict.")
        } catch let error as PortalIAPServiceError {
            #expect(error == .transactionAlreadyClaimed)
        }
    }

    private static func makeService(
        transport: IAPServiceTestTransport
    ) -> APIKitPortalIAPService {
        let client: PortalAPIClient = PortalAPIClient(
            configuration: BrowseCraftAPIConfiguration(
                baseURL: URL(string: "https://api.example.test")!
            ),
            transport: transport
        )
        return APIKitPortalIAPService(
            identityAPI: PortalIdentityAPI(client: client),
            iapAPI: PortalIAPAPI(client: client)
        )
    }
}

private final class PurchaseRefreshTestSessionStore:
    PortalSessionStoring,
    @unchecked Sendable {
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
}

private actor PurchaseRefreshTestAuthenticator:
    PortalIdentityAuthenticating {
    func register(userID: UUID) async throws -> PortalAuthenticationTokens {
        throw PortalIdentityAuthenticationError.temporarilyUnavailable
    }

    func refresh(refreshToken: String) async throws
        -> PortalAuthenticationTokens {
        throw PortalIdentityAuthenticationError.temporarilyUnavailable
    }
}

private actor PurchaseRefreshTestIAPService: PortalIAPServicing {
    struct Request: Equatable {
        let userID: UUID
        let environment: PortalPurchaseEnvironment
        let signedTransactions: [String]
        let accessToken: String
    }

    private let userID: UUID
    private(set) var lastRequest: Request?
    private(set) var lastRecoveryProof: String?

    init(userID: UUID) {
        self.userID = userID
    }

    func recoverSession(
        userID: UUID,
        signedTransaction: String
    ) async throws -> PortalAuthenticationTokens {
        self.lastRecoveryProof = signedTransaction
        return PortalAuthenticationTokens(
            userID: userID,
            accessToken: "recovered-access-token",
            refreshToken: "recovered-refresh-token",
            accessTokenExpiresAt: Date().addingTimeInterval(3_600),
            refreshTokenExpiresAt: Date().addingTimeInterval(86_400)
        )
    }

    func refreshEntitlements(
        userID: UUID,
        environment: PortalPurchaseEnvironment,
        signedTransactions: [String],
        accessToken: String
    ) async throws -> PortalEntitlementSnapshot {
        self.lastRequest = Request(
            userID: userID,
            environment: environment,
            signedTransactions: signedTransactions,
            accessToken: accessToken
        )
        return PortalEntitlementSnapshot(
            userID: self.userID,
            environment: environment,
            includedSiteSlots: 1,
            purchasedSiteSlots: 1,
            siteSlotLimit: 2,
            hasRemovedAds: false,
            activeProductIDs: ["com.xiefei.AnyPortal.site.unlock.1"],
            revision: 1,
            verifiedAt: Date()
        )
    }
}

private actor IAPServiceTestTransport: PortalAPITransport {
    private let response: PortalAPITransportResponse

    init(response: PortalAPITransportResponse) {
        self.response = response
    }

    func send(_ request: URLRequest) async throws -> PortalAPITransportResponse {
        _ = request
        return self.response
    }
}
