import BrowseCraftAPIKit
import Foundation

struct APIKitPortalIAPService: PortalIAPServicing {
    private let identityAPI: PortalIdentityAPI
    private let iapAPI: PortalIAPAPI

    init(
        identityAPI: PortalIdentityAPI,
        iapAPI: PortalIAPAPI
    ) {
        self.identityAPI = identityAPI
        self.iapAPI = iapAPI
    }

    func recoverSession(
        userID: UUID,
        signedTransaction: String
    ) async throws -> PortalAuthenticationTokens {
        PortalSessionDiagnostics.notice(
            "event=request-start operation=iap-recover path=\(PortalAPIPath.authRecover)"
        )
        do {
            let response: PortalTokenResponse = try await self.identityAPI.recover(
                userID: userID,
                signedTransaction: signedTransaction
            )
            guard response.userID == userID else {
                throw PortalIAPServiceError.subjectMismatch
            }
            PortalSessionDiagnostics.notice(
                "event=request-success operation=iap-recover " +
                    "path=\(PortalAPIPath.authRecover)"
            )
            return PortalAuthenticationTokens(
                userID: response.userID,
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                accessTokenExpiresAt: response.expiresAt,
                refreshTokenExpiresAt: response.refreshExpiresAt
            )
        } catch {
            let mappedError: any Error = Self.map(error)
            PortalSessionDiagnostics.error(
                "event=request-failure operation=iap-recover " +
                    "path=\(PortalAPIPath.authRecover) " +
                    Self.safeErrorDescription(mappedError)
            )
            throw mappedError
        }
    }

    func refreshEntitlements(
        userID: UUID,
        environment: PortalPurchaseEnvironment,
        signedTransactions: [String],
        accessToken: String
    ) async throws -> PortalEntitlementSnapshot {
        PortalSessionDiagnostics.notice(
            "event=request-start operation=iap-entitlements-refresh " +
                "path=\(PortalAPIPath.entitlementRefresh) " +
                "environment=\(environment.rawValue) " +
                "transactionCount=\(signedTransactions.count)"
        )
        do {
            let response: PortalEntitlementSnapshotResponse =
                try await self.iapAPI.refreshEntitlements(
                    userID: userID,
                    environment: Self.apiEnvironment(environment),
                    signedTransactions: signedTransactions,
                    accessToken: accessToken
                )
            guard response.userID == userID else {
                throw PortalIAPServiceError.subjectMismatch
            }
            guard response.environment.rawValue == environment.rawValue,
                  response.includedSiteSlots >= 1,
                  response.purchasedSiteSlots >= 0,
                  response.siteSlotLimit ==
                    response.includedSiteSlots + response.purchasedSiteSlots,
                  response.revision >= 0 else {
                throw PortalIAPServiceError.responseOutcomeUnknown
            }

            PortalSessionDiagnostics.notice(
                "event=request-success operation=iap-entitlements-refresh " +
                    "path=\(PortalAPIPath.entitlementRefresh) " +
                    "environment=\(response.environment.rawValue) " +
                    "revision=\(response.revision) " +
                    "activeProductCount=\(response.activeProductIDs.count) " +
                    "siteSlotLimit=\(response.siteSlotLimit) " +
                    "hasRemovedAds=\(response.hasRemovedAds)"
            )
            return PortalEntitlementSnapshot(
                userID: response.userID,
                environment: environment,
                includedSiteSlots: response.includedSiteSlots,
                purchasedSiteSlots: response.purchasedSiteSlots,
                siteSlotLimit: response.siteSlotLimit,
                hasRemovedAds: response.hasRemovedAds,
                activeProductIDs: Set(response.activeProductIDs),
                revision: response.revision,
                verifiedAt: response.verifiedAt
            )
        } catch {
            let mappedError: any Error = Self.map(error)
            PortalSessionDiagnostics.error(
                "event=request-failure operation=iap-entitlements-refresh " +
                    "path=\(PortalAPIPath.entitlementRefresh) " +
                    Self.safeErrorDescription(mappedError)
            )
            throw mappedError
        }
    }

    private static func apiEnvironment(
        _ environment: PortalPurchaseEnvironment
    ) -> PortalIAPEnvironment {
        switch environment {
        case .sandbox:
            return .sandbox
        case .production:
            return .production
        }
    }

    private static func map(_ error: any Error) -> any Error {
        if error is CancellationError {
            return CancellationError()
        }
        if let serviceError: PortalIAPServiceError =
            error as? PortalIAPServiceError {
            return serviceError
        }
        if error is PortalIAPRequestValidationError {
            return PortalIAPServiceError.invalidRequest
        }
        guard let apiError: PortalAPIError = error as? PortalAPIError else {
            return PortalIAPServiceError.temporarilyUnavailable
        }

        switch apiError {
        case .transportFailed, .invalidHTTPResponse:
            return PortalIAPServiceError.temporarilyUnavailable
        case .responseDecodingFailed:
            return PortalIAPServiceError.responseOutcomeUnknown
        case .server(let statusCode, let body):
            switch body.code {
            case "AUTH_FORBIDDEN":
                return PortalIAPServiceError.recoveryNotAllowed
            case "AUTH_REQUIRED", "AUTH_ACCESS_TOKEN_EXPIRED",
                 "AUTH_ACCESS_TOKEN_INVALID":
                return PortalIAPServiceError.sessionRejected
            case "AUTH_SUBJECT_MISMATCH":
                return PortalIAPServiceError.subjectMismatch
            case "IAP_UNVERIFIED_TRANSACTION":
                return PortalIAPServiceError.unverifiedTransaction
            case "IAP_BUNDLE_MISMATCH":
                return PortalIAPServiceError.bundleMismatch
            case "IAP_ENVIRONMENT_MISMATCH":
                return PortalIAPServiceError.environmentMismatch
            case "IAP_UNKNOWN_PRODUCT":
                return PortalIAPServiceError.unknownProduct
            case "IAP_ACCOUNT_TOKEN_MISSING":
                return PortalIAPServiceError.accountTokenMissing
            case "IAP_REVOKED":
                return PortalIAPServiceError.revokedTransaction
            case "IAP_ACCOUNT_MISMATCH":
                return PortalIAPServiceError.accountMismatch
            case "IAP_TRANSACTION_ALREADY_CLAIMED":
                return PortalIAPServiceError.transactionAlreadyClaimed
            case "IAP_RATE_LIMITED":
                return PortalIAPServiceError.rateLimited
            case "AUTH_INVALID_REQUEST", "IAP_INVALID_REQUEST",
                 "IAP_REQUEST_TOO_LARGE":
                return PortalIAPServiceError.invalidRequest
            default:
                if statusCode == 404 || statusCode == 405 ||
                    statusCode == 408 || statusCode >= 500 {
                    return PortalIAPServiceError.temporarilyUnavailable
                }
                return PortalIAPServiceError.contractRejected(code: body.code)
            }
        case .unexpectedStatusCode(let statusCode):
            if statusCode == 404 || statusCode == 405 ||
                statusCode == 408 || statusCode == 429 ||
                statusCode >= 500 {
                return PortalIAPServiceError.temporarilyUnavailable
            }
            return PortalIAPServiceError.contractRejected(
                code: "HTTP_\(statusCode)"
            )
        case .invalidEndpoint, .requestEncodingFailed:
            return PortalIAPServiceError.clientConfiguration
        }
    }

    private static func safeErrorDescription(_ error: any Error) -> String {
        if error is CancellationError {
            return "category=cancelled"
        }
        guard let serviceError: PortalIAPServiceError =
            error as? PortalIAPServiceError else {
            return "category=unexpected"
        }

        switch serviceError {
        case .temporarilyUnavailable:
            return "category=temporarily-unavailable"
        case .responseOutcomeUnknown:
            return "category=response-outcome-unknown"
        case .recoveryNotAllowed:
            return "category=recovery-not-allowed"
        case .sessionRejected:
            return "category=session-rejected"
        case .subjectMismatch:
            return "category=subject-mismatch"
        case .unverifiedTransaction:
            return "category=unverified-transaction"
        case .bundleMismatch:
            return "category=bundle-mismatch"
        case .environmentMismatch:
            return "category=environment-mismatch"
        case .unknownProduct:
            return "category=unknown-product"
        case .accountTokenMissing:
            return "category=account-token-missing"
        case .revokedTransaction:
            return "category=revoked-transaction"
        case .accountMismatch:
            return "category=account-mismatch"
        case .transactionAlreadyClaimed:
            return "category=transaction-already-claimed"
        case .rateLimited:
            return "category=rate-limited"
        case .invalidRequest:
            return "category=invalid-request"
        case .contractRejected(let code):
            return "category=contract-rejected code=\(code)"
        case .clientConfiguration:
            return "category=client-configuration"
        }
    }
}
