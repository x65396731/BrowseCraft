import Foundation

struct PortalAuthenticationTokens: Codable, Equatable, Sendable {
    let userID: UUID
    let accessToken: String
    let refreshToken: String
    let accessTokenExpiresAt: Date
    let refreshTokenExpiresAt: Date
}

/// 中文注释：完整认证状态编码为一个 Keychain 数据项，Token 轮换时不会产生分字段半更新。
struct PortalSessionPersistence: Codable, Sendable {
    static let currentSchemaVersion: Int = 2

    let schemaVersion: Int
    let userID: UUID
    var credentials: PortalAuthenticationTokens

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        userID: UUID,
        credentials: PortalAuthenticationTokens
    ) {
        self.schemaVersion = schemaVersion
        self.userID = userID
        self.credentials = credentials
    }
}

enum PortalSessionStatus: String, Equatable, Sendable {
    case signedOut
    case authenticating
    case authenticated
    case temporarilyUnavailable
    case userDisabled
    case accountConflict
}

struct PortalSessionSnapshot: Equatable, Sendable {
    let status: PortalSessionStatus
    let userID: UUID
    let accessTokenExpiresAt: Date?
    let refreshTokenExpiresAt: Date?
}
