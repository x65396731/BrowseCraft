import CryptoKit
import Foundation
import OSLog

enum IAPDiagnostics {
    private static let logger: Logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "BrowseCraft",
        category: "IdentityIAP"
    )

    static func notice(_ message: String) {
        Self.logger.notice(
            "[BrowseCraftIdentityIAP] \(message, privacy: .public)"
        )
    }

    static func error(_ message: String) {
        Self.logger.error(
            "[BrowseCraftIdentityIAP] \(message, privacy: .public)"
        )
    }

    static func hash(_ userID: UUID) -> String {
        return Self.hash(userID.uuidString)
    }

    static func hash(transactionID: UInt64) -> String {
        return Self.hash(String(transactionID))
    }

    static func safeErrorCode(_ error: any Error) -> String {
        if error is CancellationError {
            return "cancelled"
        }
        if let error = error as? CloudAppUserIdentityStoreError {
            switch error {
            case .accountUnavailable:
                return "icloud-account-unavailable"
            case .accessDenied:
                return "icloud-access-denied"
            case .malformedRecord:
                return "icloud-identity-malformed"
            case .unsupportedSchemaVersion:
                return "icloud-identity-schema-unsupported"
            case .temporarilyUnavailable:
                return "icloud-temporarily-unavailable"
            case .operationFailed:
                return "icloud-operation-failed"
            }
        }
        if let error = error as? StoreKitPurchaseIdentityAuthorizationError {
            switch error {
            case .notAssociated:
                return "identity-not-associated"
            case .identityMismatch:
                return "identity-mismatch"
            case .activeUserChanged:
                return "active-user-changed"
            case .unsupportedSchemaVersion:
                return "identity-schema-unsupported"
            }
        }
        if let error = error as? StoreKitTransactionIdentityError {
            switch error {
            case .missingAppAccountToken:
                return "app-account-token-missing"
            case .accountMismatch:
                return "app-account-token-mismatch"
            }
        }
        if let error = error as? StoreKitPortalPurchaseSubmissionError {
            switch error {
            case .xcodeEnvironmentUnsupported:
                return "xcode-environment-unsupported"
            case .unsupportedEnvironment:
                return "storekit-environment-unsupported"
            case .transactionProductMismatch:
                return "transaction-product-mismatch"
            case .snapshotContractMismatch:
                return "snapshot-contract-mismatch"
            case .purchasedProductMissing:
                return "purchased-product-missing"
            }
        }
        if let error = error as? PortalPurchaseEntitlementRefreshError {
            switch error {
            case .activeUserChanged:
                return "active-user-changed"
            case .sessionUnavailable:
                return "portal-session-unavailable"
            case .snapshotMismatch:
                return "portal-snapshot-mismatch"
            }
        }
        if let error = error as? PortalIAPServiceError {
            switch error {
            case .temporarilyUnavailable:
                return "portal-temporarily-unavailable"
            case .responseOutcomeUnknown:
                return "portal-response-outcome-unknown"
            case .recoveryNotAllowed:
                return "portal-recovery-not-allowed"
            case .sessionRejected:
                return "portal-session-rejected"
            case .subjectMismatch:
                return "portal-subject-mismatch"
            case .unverifiedTransaction:
                return "portal-unverified-transaction"
            case .bundleMismatch:
                return "portal-bundle-mismatch"
            case .environmentMismatch:
                return "portal-environment-mismatch"
            case .unknownProduct:
                return "portal-unknown-product"
            case .accountTokenMissing:
                return "portal-account-token-missing"
            case .revokedTransaction:
                return "portal-revoked-transaction"
            case .accountMismatch:
                return "portal-account-mismatch"
            case .transactionAlreadyClaimed:
                return "portal-transaction-already-claimed"
            case .rateLimited:
                return "portal-rate-limited"
            case .invalidRequest:
                return "portal-invalid-request"
            case .contractRejected(let code):
                return "portal-contract-rejected:\(code)"
            case .clientConfiguration:
                return "portal-client-configuration"
            }
        }
        return String(reflecting: type(of: error))
    }

    private static func hash(_ value: String) -> String {
        let digest: SHA256.Digest = SHA256.hash(data: Data(value.utf8))
        return digest.prefix(8).map { byte in
            String(format: "%02x", byte)
        }.joined()
    }
}

enum PortalPurchaseEnvironment: String, Codable, Hashable, Sendable {
    case sandbox = "Sandbox"
    case production = "Production"
}

struct PortalEntitlementSnapshot: Equatable, Sendable {
    let userID: UUID
    let environment: PortalPurchaseEnvironment
    let includedSiteSlots: Int
    let purchasedSiteSlots: Int
    let siteSlotLimit: Int
    let hasRemovedAds: Bool
    let activeProductIDs: Set<String>
    let revision: Int
    let verifiedAt: Date
}

enum PortalIAPServiceError: Error, Equatable, Sendable {
    case temporarilyUnavailable
    case responseOutcomeUnknown
    case recoveryNotAllowed
    case sessionRejected
    case subjectMismatch
    case unverifiedTransaction
    case bundleMismatch
    case environmentMismatch
    case unknownProduct
    case accountTokenMissing
    case revokedTransaction
    case accountMismatch
    case transactionAlreadyClaimed
    case rateLimited
    case invalidRequest
    case contractRejected(code: String)
    case clientConfiguration
}

enum PortalPurchaseEntitlementRefreshError: Error, Equatable, Sendable {
    case activeUserChanged
    case sessionUnavailable
    case snapshotMismatch
}

/// 中文注释：只封装 Portal IAP 网络合同；调用时机必须由用户主动购买/恢复状态机决定。
protocol PortalIAPServicing: Sendable {
    func recoverSession(
        userID: UUID,
        signedTransaction: String
    ) async throws -> PortalAuthenticationTokens

    func refreshEntitlements(
        userID: UUID,
        environment: PortalPurchaseEnvironment,
        signedTransactions: [String],
        accessToken: String
    ) async throws -> PortalEntitlementSnapshot
}

/// 中文注释：购买与 StoreKit 生命周期更新只使用现有 Portal Session；
/// 只有用户主动恢复购买时才允许通过 Apple JWS 恢复 Session。
actor PortalPurchaseEntitlementRefreshCoordinator {
    private let activeAppUser: any ActiveAppUserProviding
    private let portalSessionCoordinator: PortalSessionCoordinator
    private let portalIAPService: any PortalIAPServicing

    init(
        activeAppUser: any ActiveAppUserProviding,
        portalSessionCoordinator: PortalSessionCoordinator,
        portalIAPService: any PortalIAPServicing
    ) {
        self.activeAppUser = activeAppUser
        self.portalSessionCoordinator = portalSessionCoordinator
        self.portalIAPService = portalIAPService
    }

    func refreshPurchasedEntitlements(
        userID: UUID,
        environment: PortalPurchaseEnvironment,
        signedTransaction: String
    ) async throws -> PortalEntitlementSnapshot {
        return try await self.refreshEntitlements(
            userID: userID,
            environment: environment,
            signedTransaction: signedTransaction,
            flow: "purchase"
        )
    }

    func refreshUpdatedEntitlements(
        userID: UUID,
        environment: PortalPurchaseEnvironment,
        signedTransaction: String
    ) async throws -> PortalEntitlementSnapshot {
        return try await self.refreshEntitlements(
            userID: userID,
            environment: environment,
            signedTransaction: signedTransaction,
            flow: "transaction-update"
        )
    }

    private func refreshEntitlements(
        userID: UUID,
        environment: PortalPurchaseEnvironment,
        signedTransaction: String,
        flow: String
    ) async throws -> PortalEntitlementSnapshot {
        IAPDiagnostics.notice(
            "event=\(flow)-refresh-started " +
                "userHash=\(IAPDiagnostics.hash(userID)) " +
                "environment=\(environment.rawValue)"
        )
        try self.requireActiveUser(userID)
        guard let accessToken: String =
            await self.portalSessionCoordinator.validAccessToken() else {
            IAPDiagnostics.error(
                "event=\(flow)-refresh-failed reason=portal-session-unavailable"
            )
            throw PortalPurchaseEntitlementRefreshError.sessionUnavailable
        }
        try self.requireActiveUser(userID)

        let snapshot: PortalEntitlementSnapshot =
            try await self.portalIAPService.refreshEntitlements(
                userID: userID,
                environment: environment,
                signedTransactions: [signedTransaction],
                accessToken: accessToken
            )

        try self.requireActiveUser(userID)
        guard snapshot.userID == userID,
              snapshot.environment == environment else {
            IAPDiagnostics.error(
                "event=\(flow)-refresh-failed reason=snapshot-mismatch " +
                    "environment=\(environment.rawValue)"
            )
            throw PortalPurchaseEntitlementRefreshError.snapshotMismatch
        }
        IAPDiagnostics.notice(
            "event=\(flow)-refresh-succeeded " +
                "environment=\(environment.rawValue) " +
                "revision=\(snapshot.revision) " +
                "activeProductCount=\(snapshot.activeProductIDs.count)"
        )
        return snapshot
    }

    /// 中文注释：只有用户点击 Restore Purchases 后才允许用 Apple JWS 恢复 Session 并刷新完整权益。
    func restoreEntitlements(
        userID: UUID,
        environment: PortalPurchaseEnvironment,
        signedTransactions: [String],
        recoveryProof: String
    ) async throws -> PortalEntitlementSnapshot {
        IAPDiagnostics.notice(
            "event=restore-refresh-started " +
                "userHash=\(IAPDiagnostics.hash(userID)) " +
                "environment=\(environment.rawValue) " +
                "transactionCount=\(signedTransactions.count)"
        )
        try self.requireActiveUser(userID)
        guard signedTransactions.isEmpty == false,
              recoveryProof.isEmpty == false else {
            IAPDiagnostics.error(
                "event=restore-refresh-failed reason=empty-transactions"
            )
            throw PortalIAPServiceError.invalidRequest
        }

        let accessToken: String
        if let existingAccessToken: String =
            await self.portalSessionCoordinator.validAccessToken() {
            IAPDiagnostics.notice(
                "event=restore-session source=existing"
            )
            accessToken = existingAccessToken
        } else {
            IAPDiagnostics.notice(
                "event=restore-session source=recovery-request"
            )
            let recoveredCredentials: PortalAuthenticationTokens =
                try await self.portalIAPService.recoverSession(
                    userID: userID,
                    signedTransaction: recoveryProof
                )
            try self.requireActiveUser(userID)
            try await self.portalSessionCoordinator.installRecoveredSession(
                recoveredCredentials,
                for: userID
            )
            IAPDiagnostics.notice(
                "event=restore-session source=recovery-installed"
            )
            accessToken = recoveredCredentials.accessToken
        }

        try self.requireActiveUser(userID)
        let snapshot: PortalEntitlementSnapshot =
            try await self.portalIAPService.refreshEntitlements(
                userID: userID,
                environment: environment,
                signedTransactions: signedTransactions,
                accessToken: accessToken
            )
        try self.requireActiveUser(userID)
        guard snapshot.userID == userID,
              snapshot.environment == environment else {
            IAPDiagnostics.error(
                "event=restore-refresh-failed reason=snapshot-mismatch " +
                    "environment=\(environment.rawValue)"
            )
            throw PortalPurchaseEntitlementRefreshError.snapshotMismatch
        }
        IAPDiagnostics.notice(
            "event=restore-refresh-succeeded " +
                "environment=\(environment.rawValue) " +
                "revision=\(snapshot.revision) " +
                "activeProductCount=\(snapshot.activeProductIDs.count)"
        )
        return snapshot
    }

    private func requireActiveUser(_ expectedUserID: UUID) throws {
        guard self.activeAppUser.currentUserID == expectedUserID else {
            IAPDiagnostics.error(
                "event=portal-refresh-failed reason=active-user-changed"
            )
            throw PortalPurchaseEntitlementRefreshError.activeUserChanged
        }
    }
}
