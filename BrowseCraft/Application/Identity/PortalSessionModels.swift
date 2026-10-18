import Foundation

struct PortalAuthenticationTokens: Codable, Equatable, Sendable {
    let userID: UUID
    let accessToken: String
    let refreshToken: String
    let accessTokenExpiresAt: Date
    let refreshTokenExpiresAt: Date
}

/// 中文注释：Apple 登录交换的结果：会话凭据，加上这次登录是否新建了账号、建号事务里入账了多少新户赠送
/// （Campaign-And-Rate-Notices-Design.md 第五节）。后两项只用来决定是否触发欢迎页，不进 Keychain，
/// App 也不据此入账（`BCA-SYNC-012`）；旧服务端不带时按老用户处理。
struct PortalAppleAuthentication: Equatable, Sendable {
    let tokens: PortalAuthenticationTokens
    var accountCreated: Bool = false
    var signupGrantCoins: Int = 0

    /// 新注册且拿到了赠送才欢迎；12 个月内删号重注册（没有赠送）与老用户重新登录都不欢迎。
    var welcomesNewAccount: Bool {
        return self.accountCreated && self.signupGrantCoins > 0
    }
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
