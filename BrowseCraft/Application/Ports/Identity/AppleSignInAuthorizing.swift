import Foundation

// 中文注释：Apple 授权端口由 Application 持有；AuthenticationServices 实现留在 Infrastructure。

enum AppleSignInAuthorizationError: Error, Equatable, Sendable {
    case operationInFlight
    case cancelled
    case missingIdentityToken
    case invalidIdentityTokenEncoding
    case authorizationFailed
    case presentationUnavailable
}

@MainActor
protocol AppleSignInAuthorizing: AnyObject, Sendable {
    func authorize(nonce: String) async throws -> String
}
