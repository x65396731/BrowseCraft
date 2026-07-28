import BrowseCraftAPIKit
import Foundation

struct APIKitPortalIdentityAuthenticator: PortalIdentityAuthenticating {
    private let api: PortalIdentityAPI

    init(api: PortalIdentityAPI) {
        self.api = api
    }

    func issueAppleChallenge() async throws -> PortalAppleAuthenticationChallenge {
        PortalSessionDiagnostics.notice(
            "event=request-start operation=apple-challenge " +
                "path=\(PortalAPIPath.authAppleChallenge)"
        )
        do {
            let response: PortalAppleAuthChallengeResponse =
                try await self.api.issueAppleChallenge()
            PortalSessionDiagnostics.notice(
                "event=request-success operation=apple-challenge " +
                    "path=\(PortalAPIPath.authAppleChallenge) " +
                    "expiresAt=\(response.expiresAt.ISO8601Format())"
            )
            return PortalAppleAuthenticationChallenge(
                nonce: response.nonce,
                expiresAt: response.expiresAt
            )
        } catch {
            PortalSessionDiagnostics.error(
                "event=request-failure operation=apple-challenge " +
                    "path=\(PortalAPIPath.authAppleChallenge) " +
                    Self.safeErrorDescription(error)
            )
            throw Self.map(error, operation: .appleChallenge)
        }
    }

    func authenticateWithApple(
        identityToken: String,
        nonce: String
    ) async throws -> PortalAuthenticationTokens {
        PortalSessionDiagnostics.notice(
            "event=request-start operation=apple-authenticate " +
                "path=\(PortalAPIPath.authApple)"
        )
        do {
            let response: PortalTokenResponse = try await self.api
                .authenticateWithApple(
                    identityToken: identityToken,
                    nonce: nonce
                )
            PortalSessionDiagnostics.notice(
                "event=request-success operation=apple-authenticate " +
                    "path=\(PortalAPIPath.authApple) " +
                    "accessExpiresAt=\(response.expiresAt.ISO8601Format()) " +
                    "refreshExpiresAt=\(response.refreshExpiresAt.ISO8601Format())"
            )
            return Self.tokens(from: response)
        } catch {
            PortalSessionDiagnostics.error(
                "event=request-failure operation=apple-authenticate " +
                    "path=\(PortalAPIPath.authApple) " +
                    Self.safeErrorDescription(error)
            )
            throw Self.map(error, operation: .appleAuthenticate)
        }
    }

    func refresh(refreshToken: String) async throws -> PortalAuthenticationTokens {
        PortalSessionDiagnostics.notice(
            "event=request-start operation=refresh path=\(PortalAPIPath.authRefresh)"
        )
        do {
            let response: PortalTokenResponse = try await self.api.refresh(
                refreshToken: refreshToken
            )
            PortalSessionDiagnostics.notice(
                "event=request-success operation=refresh path=\(PortalAPIPath.authRefresh) " +
                    "accessExpiresAt=\(response.expiresAt.ISO8601Format()) " +
                    "refreshExpiresAt=\(response.refreshExpiresAt.ISO8601Format())"
            )
            return Self.tokens(from: response)
        } catch {
            PortalSessionDiagnostics.error(
                "event=request-failure operation=refresh path=\(PortalAPIPath.authRefresh) " +
                    Self.safeErrorDescription(error)
            )
            throw Self.map(error, operation: .refresh)
        }
    }

    func logout(refreshToken: String, accessToken: String) async throws {
        do {
            try await self.api.logout(
                refreshToken: refreshToken,
                accessToken: accessToken
            )
        } catch {
            throw Self.map(error, operation: .logout)
        }
    }

    func logoutAll(accessToken: String) async throws {
        do {
            try await self.api.logoutAll(accessToken: accessToken)
        } catch {
            throw Self.map(error, operation: .logoutAll)
        }
    }

    private static func tokens(from response: PortalTokenResponse) -> PortalAuthenticationTokens {
        return PortalAuthenticationTokens(
            userID: response.userID,
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            accessTokenExpiresAt: response.expiresAt,
            refreshTokenExpiresAt: response.refreshExpiresAt
        )
    }

    private static func map(
        _ error: any Error,
        operation: PortalIdentityOperation
    ) -> any Error {
        if error is CancellationError {
            return CancellationError()
        }
        guard let apiError: PortalAPIError = error as? PortalAPIError else {
            return PortalIdentityAuthenticationError.temporarilyUnavailable
        }

        switch apiError {
        case .transportFailed, .invalidHTTPResponse:
            return PortalIdentityAuthenticationError.temporarilyUnavailable
        case .responseDecodingFailed:
            return PortalIdentityAuthenticationError.responseOutcomeUnknown
        case .server(let statusCode, let body):
            switch body.code {
            case "AUTH_APPLE_CHALLENGE_INVALID":
                return PortalIdentityAuthenticationError.appleChallengeRejected
            case "AUTH_APPLE_TOKEN_INVALID", "AUTH_APPLE_TOKEN_EXPIRED":
                return PortalIdentityAuthenticationError.appleIdentityRejected
            case "AUTH_USER_DISABLED":
                return PortalIdentityAuthenticationError.userDisabled
            case "AUTH_REFRESH_TOKEN_INVALID", "AUTH_REFRESH_TOKEN_EXPIRED":
                return PortalIdentityAuthenticationError.refreshRejected
            default:
                if statusCode == 404 || statusCode == 405 || statusCode == 408 ||
                    statusCode == 429 || statusCode >= 500 {
                    return PortalIdentityAuthenticationError.temporarilyUnavailable
                }
                return PortalIdentityAuthenticationError.contractRejected(code: body.code)
            }
        case .unexpectedStatusCode(let statusCode):
            if statusCode == 404 || statusCode == 405 || statusCode == 408 ||
                statusCode == 429 || statusCode >= 500 {
                return PortalIdentityAuthenticationError.temporarilyUnavailable
            }
            return PortalIdentityAuthenticationError.contractRejected(
                code: "HTTP_\(statusCode)_\(operation.rawValue)"
            )
        case .invalidEndpoint, .requestEncodingFailed:
            return PortalIdentityAuthenticationError.clientConfiguration
        }
    }

    private static func safeErrorDescription(_ error: any Error) -> String {
        if error is CancellationError {
            return "category=cancelled"
        }
        guard let apiError: PortalAPIError = error as? PortalAPIError else {
            return "category=unexpected"
        }

        switch apiError {
        case .invalidEndpoint:
            return "category=invalid-endpoint"
        case .invalidHTTPResponse:
            return "category=invalid-http-response"
        case .requestEncodingFailed:
            return "category=request-encoding-failed"
        case .transportFailed:
            return "category=transport-failed"
        case .server(let statusCode, let body):
            return "category=server status=\(statusCode) code=\(body.code) " +
                "requestId=\(body.requestID)"
        case .unexpectedStatusCode(let statusCode):
            return "category=unexpected-status status=\(statusCode)"
        case .responseDecodingFailed:
            return "category=response-decoding-failed"
        }
    }
}

private enum PortalIdentityOperation: String {
    case appleChallenge = "apple-challenge"
    case appleAuthenticate = "apple-authenticate"
    case refresh
    case logout
    case logoutAll = "logout-all"
}
