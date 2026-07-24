import Foundation

enum PortalIdentityAuthenticationError: Error, Equatable, Sendable {
    case temporarilyUnavailable
    case registrationAlreadyExists
    case refreshRejected
    case subjectMismatch
    case responseOutcomeUnknown
    case contractRejected(code: String)
    case clientConfiguration
}

protocol PortalIdentityAuthenticating: Sendable {
    func register(userID: UUID) async throws -> PortalAuthenticationTokens
    func refresh(refreshToken: String) async throws -> PortalAuthenticationTokens
}
