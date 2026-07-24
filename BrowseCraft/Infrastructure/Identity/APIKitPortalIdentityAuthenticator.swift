import BrowseCraftAPIKit
import Foundation

struct APIKitPortalIdentityAuthenticator: PortalIdentityAuthenticating {
    private let api: PortalIdentityAPI

    init(api: PortalIdentityAPI) {
        self.api = api
    }

    func register(userID: UUID) async throws -> PortalAuthenticationTokens {
        do {
            return Self.tokens(from: try await self.api.register(userID: userID))
        } catch {
            throw Self.map(error, operation: .register)
        }
    }

    func refresh(refreshToken: String) async throws -> PortalAuthenticationTokens {
        do {
            return Self.tokens(from: try await self.api.refresh(refreshToken: refreshToken))
        } catch {
            throw Self.map(error, operation: .refresh)
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
            case "AUTH_USER_ALREADY_REGISTERED":
                return PortalIdentityAuthenticationError.registrationAlreadyExists
            case "AUTH_REFRESH_TOKEN_INVALID", "AUTH_REFRESH_TOKEN_EXPIRED":
                return PortalIdentityAuthenticationError.refreshRejected
            case "AUTH_SUBJECT_MISMATCH":
                return PortalIdentityAuthenticationError.subjectMismatch
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
}

private enum PortalIdentityOperation: String {
    case register
    case refresh
}
