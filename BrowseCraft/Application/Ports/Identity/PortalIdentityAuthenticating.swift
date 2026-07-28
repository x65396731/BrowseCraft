import Foundation

enum PortalIdentityAuthenticationError: Error, Equatable, Sendable {
    case temporarilyUnavailable
    case appleChallengeRejected
    case appleIdentityRejected
    case userDisabled
    case refreshRejected
    case responseOutcomeUnknown
    case contractRejected(code: String)
    case clientConfiguration
}

struct PortalAppleAuthenticationChallenge: Equatable, Sendable {
    let nonce: String
    let expiresAt: Date
}

protocol PortalIdentityAuthenticating: Sendable {
    func issueAppleChallenge() async throws -> PortalAppleAuthenticationChallenge
    func authenticateWithApple(
        identityToken: String,
        nonce: String
    ) async throws -> PortalAuthenticationTokens
    func refresh(refreshToken: String) async throws -> PortalAuthenticationTokens
    func logout(refreshToken: String, accessToken: String) async throws
    func logoutAll(accessToken: String) async throws
}
