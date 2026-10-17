import BrowseCraftLog
import Foundation

/// 中文注释：内购与身份流程的错误码映射。日志本身走 `AppLog`（Logging-Design.md），这里只把已知错误映射成有限取值的机器码。
enum IAPDiagnostics {
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
            case .signInRequired:
                return "portal-sign-in-required"
            case .activeUserChanged:
                return "active-user-changed"
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
    func refreshEntitlements(
        userID: UUID,
        environment: PortalPurchaseEnvironment,
        signedTransactions: [String],
        accessToken: String
    ) async throws -> PortalEntitlementSnapshot
}

/// 中文注释：购买、恢复与 StoreKit 生命周期更新都只使用现有 Portal Session。
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
        AppLog.notice(.purchase, "\(flow)-refresh-started", [
            "userHash": .id(userID),
            "environment": .enumValue(environment)
        ])
        try self.requireActiveUser(userID)
        try await self.requireAuthenticatedPortalUser(userID)
        guard let accessToken: String =
            await self.portalSessionCoordinator.validAccessToken() else {
            AppLog.error(.purchase, "\(flow)-refresh-failed", ["reason": .code("portal-session-unavailable")])
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
            AppLog.error(.purchase, "\(flow)-refresh-failed", [
                "reason": .code("snapshot-mismatch"),
                "environment": .enumValue(environment)
            ])
            throw PortalPurchaseEntitlementRefreshError.snapshotMismatch
        }
        AppLog.notice(.purchase, "\(flow)-refresh-succeeded", [
            "environment": .enumValue(environment),
            "revision": .code("\(snapshot.revision)"),
            "activeProductCount": .int(snapshot.activeProductIDs.count)
        ])
        return snapshot
    }

    /// 中文注释：恢复购买必须先完成 Apple 登录，再把 StoreKit 可见交易提交现有 IAP 接口。
    func restoreEntitlements(
        userID: UUID,
        environment: PortalPurchaseEnvironment,
        signedTransactions: [String]
    ) async throws -> PortalEntitlementSnapshot {
        AppLog.notice(.purchase, "restore-refresh-started", [
            "userHash": .id(userID),
            "environment": .enumValue(environment),
            "transactionCount": .int(signedTransactions.count)
        ])
        try self.requireActiveUser(userID)
        try await self.requireAuthenticatedPortalUser(userID)
        guard signedTransactions.isEmpty == false else {
            AppLog.error(.purchase, "restore-refresh-failed", ["reason": .code("empty-transactions")])
            throw PortalIAPServiceError.invalidRequest
        }

        guard let accessToken: String =
                await self.portalSessionCoordinator.validAccessToken() else {
            throw PortalPurchaseEntitlementRefreshError.sessionUnavailable
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
            AppLog.error(.purchase, "restore-refresh-failed", [
                "reason": .code("snapshot-mismatch"),
                "environment": .enumValue(environment)
            ])
            throw PortalPurchaseEntitlementRefreshError.snapshotMismatch
        }
        AppLog.notice(.purchase, "restore-refresh-succeeded", [
            "environment": .enumValue(environment),
            "revision": .code("\(snapshot.revision)"),
            "activeProductCount": .int(snapshot.activeProductIDs.count)
        ])
        return snapshot
    }

    private func requireActiveUser(_ expectedUserID: UUID) throws {
        guard self.activeAppUser.currentUserID == expectedUserID else {
            AppLog.error(.purchase, "portal-refresh-failed", ["reason": .code("active-user-changed")])
            throw PortalPurchaseEntitlementRefreshError.activeUserChanged
        }
    }

    private func requireAuthenticatedPortalUser(
        _ expectedUserID: UUID
    ) async throws {
        guard await self.portalSessionCoordinator.authenticatedUserID() ==
                expectedUserID else {
            throw PortalPurchaseEntitlementRefreshError.sessionUnavailable
        }
    }
}
