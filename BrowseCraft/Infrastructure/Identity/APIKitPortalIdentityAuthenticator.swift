import BrowseCraftAPIKit
import BrowseCraftLog
import Foundation

struct APIKitPortalIdentityAuthenticator: PortalIdentityAuthenticating {
    private let api: PortalIdentityAPI

    init(api: PortalIdentityAPI) {
        self.api = api
    }

    func issueAppleChallenge() async throws -> PortalAppleAuthenticationChallenge {
        AppLog.notice(.identity, "request-start", [
            "operation": .code("apple-challenge"),
            "path": .code(PortalAPIPath.authAppleChallenge)
        ])
        do {
            let response: PortalAppleAuthChallengeResponse =
                try await self.api.issueAppleChallenge()
            AppLog.notice(.identity, "request-success", [
                "operation": .code("apple-challenge"),
                "path": .code(PortalAPIPath.authAppleChallenge),
                "expiresAt": .code("\(response.expiresAt.ISO8601Format())")
            ])
            return PortalAppleAuthenticationChallenge(
                nonce: response.nonce,
                expiresAt: response.expiresAt
            )
        } catch {
            AppLog.error(.identity, "request-failure", [
                "operation": .code("apple-challenge"),
                "path": .code(PortalAPIPath.authAppleChallenge),
                "message": .code("\(Self.safeErrorDescription(error))")
            ])
            throw Self.map(error, operation: .appleChallenge)
        }
    }

    func authenticateWithApple(
        identityToken: String,
        nonce: String
    ) async throws -> PortalAppleAuthentication {
        AppLog.notice(.identity, "request-start", [
            "operation": .code("apple-authenticate"),
            "path": .code(PortalAPIPath.authApple)
        ])
        do {
            let response: PortalTokenResponse = try await self.api
                .authenticateWithApple(
                    identityToken: identityToken,
                    nonce: nonce
                )
            AppLog.notice(.identity, "request-success", [
                "operation": .code("apple-authenticate"),
                "path": .code(PortalAPIPath.authApple),
                "accessExpiresAt": .code("\(response.expiresAt.ISO8601Format())"),
                "refreshExpiresAt": .code("\(response.refreshExpiresAt.ISO8601Format())"),
                "accountCreated": .bool(response.accountCreated ?? false)
            ])
            return PortalAppleAuthentication(
                tokens: Self.tokens(from: response),
                accountCreated: response.accountCreated ?? false,
                signupGrantCoins: response.signupGrantCoins ?? 0
            )
        } catch {
            AppLog.error(.identity, "request-failure", [
                "operation": .code("apple-authenticate"),
                "path": .code(PortalAPIPath.authApple),
                "message": .code("\(Self.safeErrorDescription(error))")
            ])
            throw Self.map(error, operation: .appleAuthenticate)
        }
    }

    func refresh(refreshToken: String) async throws -> PortalAuthenticationTokens {
        AppLog.notice(.identity, "request-start", [
            "operation": .code("refresh"),
            "path": .code(PortalAPIPath.authRefresh)
        ])
        do {
            let response: PortalTokenResponse = try await self.api.refresh(
                refreshToken: refreshToken
            )
            AppLog.notice(.identity, "request-success", [
                "operation": .code("refresh"),
                "path": .code(PortalAPIPath.authRefresh),
                "accessExpiresAt": .code("\(response.expiresAt.ISO8601Format())"),
                "refreshExpiresAt": .code("\(response.refreshExpiresAt.ISO8601Format())")
            ])
            return Self.tokens(from: response)
        } catch {
            AppLog.error(.identity, "request-failure", [
                "operation": .code("refresh"),
                "path": .code(PortalAPIPath.authRefresh),
                "message": .code("\(Self.safeErrorDescription(error))")
            ])
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
