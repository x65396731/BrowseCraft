import BrowseCraftAPIKit
import BrowseCraftLog
import Foundation

/// `PortalAccountDeleting` 的 PortalCore 适配器（`POST /v1/account/deletion`、探测用的 `GET /v1/account`）。
/// 失败代码到成因的对应见 docs/design/Account-Deletion-Design.md 第八节。
struct APIKitPortalAccountDeletionService: PortalAccountDeleting {
    private let api: PortalAccountAPI

    init(api: PortalAccountAPI) {
        self.api = api
    }

    func deleteAccount(
        accessToken: String,
        identityToken: String,
        nonce: String,
        authorizationCode: String
    ) async throws -> AccountDeletionServerResult {
        do {
            let response: PortalAccountDeletionResponse = try await self.api.deleteAccount(
                accessToken: accessToken,
                request: PortalAccountDeletionRequest(
                    identityToken: identityToken,
                    nonce: nonce,
                    authorizationCode: authorizationCode
                )
            )
            return AccountDeletionServerResult(
                appleRevocationFailed: response.appleAuthorization != .revoked
            )
        } catch {
            throw Self.map(error)
        }
    }

    func probeAccount(accessToken: String) async -> AccountDeletionProbeResult {
        do {
            _ = try await self.api.fetchAccount(accessToken: accessToken)
            return .exists
        } catch PortalAPIError.server(let statusCode, _) where statusCode == 401 {
            return .deleted
        } catch PortalAPIError.unexpectedStatusCode(let statusCode) where statusCode == 401 {
            return .deleted
        } catch {
            AppLog.error(.identity, "account-existence-probe-failed", ["error": .error(error)])
            return .unknown
        }
    }

    static func map(_ error: any Error) -> AccountDeletionServiceError {
        guard let apiError: PortalAPIError = error as? PortalAPIError else {
            return .outcomeUnknown
        }
        switch apiError {
        case .transportFailed, .invalidHTTPResponse, .responseDecodingFailed:
            return .outcomeUnknown
        case .invalidEndpoint, .requestEncodingFailed:
            return .rejected(code: "client-configuration")
        case .unexpectedStatusCode(let statusCode):
            // 中文注释：没有错误信封的 5xx 多半来自网关，请求可能已经在服务端提交了。
            return statusCode >= 500 ? .outcomeUnknown : .rejected(code: "HTTP_\(statusCode)")
        case .server(let statusCode, let body):
            switch body.code {
            case "AUTH_REQUIRED", "AUTH_ACCESS_TOKEN_EXPIRED", "AUTH_ACCESS_TOKEN_INVALID":
                return .sessionExpired
            case "AUTH_APPLE_CHALLENGE_INVALID", "AUTH_APPLE_TOKEN_EXPIRED", "AUTH_APPLE_TOKEN_INVALID",
                 "ACCOUNT_DELETION_APPLE_CODE_INVALID":
                return .verificationExpired
            case "ACCOUNT_DELETION_APPLE_ACCOUNT_MISMATCH":
                return .appleAccountMismatch
            case "ACCOUNT_DELETION_APPLE_UNAVAILABLE":
                return .appleUnavailable
            case "ACCOUNT_DELETION_APPLE_NOT_CONFIGURED":
                return .notConfigured
            case "ACCOUNT_DELETION_PERSISTENCE_ERROR":
                return .persistenceFailed
            case "AUTH_RATE_LIMITED", "RATE_LIMITED":
                return .rateLimited
            default:
                if statusCode == 401 {
                    return .sessionExpired
                }
                if statusCode == 429 {
                    return .rateLimited
                }
                return .rejected(code: body.code)
            }
        }
    }
}
