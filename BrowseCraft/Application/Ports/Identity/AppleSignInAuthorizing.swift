import Foundation

// 中文注释：Apple 授权端口由 Application 持有；AuthenticationServices 实现留在 Infrastructure。

enum AppleSignInAuthorizationError: Error, Equatable, Sendable {
    case operationInFlight
    case cancelled
    case missingIdentityToken
    case invalidIdentityTokenEncoding
    case missingAuthorizationCode
    case authorizationFailed
    case presentationUnavailable
}

/// 中文注释：一次 Apple 授权交回的三样。identityToken 用于登录与删号验身；authorizationCode 只在删号时交给服务端
/// 换 token 并撤销（PortalCore 删号设计稿 D2，5 分钟内有效、只能用一次）；userIdentifier 存进 Keychain 供凭据状态查询。
/// 三者都不得写日志。
struct AppleSignInAuthorization: Equatable, Sendable, CustomStringConvertible {
    let identityToken: String
    let authorizationCode: String
    let userIdentifier: String

    var description: String {
        return "AppleSignInAuthorization(<redacted>)"
    }
}

@MainActor
protocol AppleSignInAuthorizing: AnyObject, Sendable {
    func authorize(nonce: String) async throws -> AppleSignInAuthorization
}
