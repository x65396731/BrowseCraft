import Foundation

struct PortalAuthenticationTokens: Codable, Equatable, Sendable {
    let userID: UUID
    let accessToken: String
    let refreshToken: String
    let accessTokenExpiresAt: Date
    let refreshTokenExpiresAt: Date
}

enum PortalRegistrationState: String, Codable, Equatable, Sendable {
    case neverAttempted
    case attempting
    case outcomeUnknown
    case authenticated
    case recoveryRequired
    case accountConflict
}

/// 中文注释：完整认证状态编码为一个 Keychain 数据项，Token 轮换时不会产生分字段半更新。
struct PortalSessionPersistence: Codable, Sendable {
    static let currentSchemaVersion: Int = 1

    let schemaVersion: Int
    let userID: UUID
    var registrationState: PortalRegistrationState
    var registrationAttemptID: UUID?
    var credentials: PortalAuthenticationTokens?

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        userID: UUID,
        registrationState: PortalRegistrationState = .neverAttempted,
        registrationAttemptID: UUID? = nil,
        credentials: PortalAuthenticationTokens? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.userID = userID
        self.registrationState = registrationState
        self.registrationAttemptID = registrationAttemptID
        self.credentials = credentials
    }
}

enum PortalSessionStatus: String, Equatable, Sendable {
    case notRegistered
    case registering
    case authenticated
    case temporarilyUnavailable
    case registrationOutcomeUnknown
    case recoveryRequired
    case accountConflict
}

struct PortalSessionSnapshot: Equatable, Sendable {
    let status: PortalSessionStatus
    let userID: UUID
    let accessTokenExpiresAt: Date?
    let refreshTokenExpiresAt: Date?
}
