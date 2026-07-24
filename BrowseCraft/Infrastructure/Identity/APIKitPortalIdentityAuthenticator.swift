import BrowseCraftAPIKit
import Foundation

struct APIKitPortalIdentityAuthenticator: PortalIdentityAuthenticating {
    private let api: PortalIdentityAPI

    init(api: PortalIdentityAPI) {
        self.api = api
    }

    func register(userID: UUID) async throws -> PortalAuthenticationTokens {
        PortalSessionDiagnostics.notice(
            "event=request-start operation=register path=\(PortalAPIPath.authRegister)"
        )
        do {
            let response: PortalTokenResponse = try await self.api.register(userID: userID)
            PortalSessionDiagnostics.notice(
                "event=request-success operation=register path=\(PortalAPIPath.authRegister) " +
                    "accessExpiresAt=\(response.expiresAt.ISO8601Format()) " +
                    "refreshExpiresAt=\(response.refreshExpiresAt.ISO8601Format())"
            )
            return Self.tokens(from: response)
        } catch {
            PortalSessionDiagnostics.error(
                "event=request-failure operation=register path=\(PortalAPIPath.authRegister) " +
                    Self.safeErrorDescription(error)
            )
            throw Self.map(error, operation: .register)
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
    case register
    case refresh
}
