import Foundation

// 中文注释：删除账号（docs/design/Account-Deletion-Design.md）在 Application 边界上的端口。
// 网络、GRDB、CloudKit、UserDefaults 的实现都在 Infrastructure，组合根装配。

/// 中文注释：服务端删号失败按成因归一（设计第八节）；全部表示「账号未删除」。
enum AccountDeletionServiceError: Error, Equatable, Sendable {
    case sessionExpired
    case verificationExpired
    case appleAccountMismatch
    case appleUnavailable
    case notConfigured
    case persistenceFailed
    case rateLimited
    /// 中文注释：没拿到可判读的响应（断网、超时、网关 5xx、200 却解码失败）——服务端可能已经删了，要探一次再说。
    case outcomeUnknown
    case rejected(code: String)
}

struct AccountDeletionServerResult: Equatable, Sendable {
    /// 中文注释：删除已完成，只是 Apple 授权没撤销成功——完成页要给手动停用的路径。
    let appleRevocationFailed: Bool
}

/// 中文注释：删号请求发出后 App 被杀，下次启动用当时的会话探一次账户还在不在（设计第七节）。
enum AccountDeletionProbeResult: Equatable, Sendable {
    case exists
    case deleted
    case unknown
}

protocol PortalAccountDeleting: Sendable {
    func deleteAccount(
        accessToken: String,
        identityToken: String,
        nonce: String,
        authorizationCode: String
    ) async throws -> AccountDeletionServerResult
    func probeAccount(accessToken: String) async -> AccountDeletionProbeResult
}

/// 中文注释：删号只借用会话的三样能力；`PortalSessionCoordinator` 在 Application 内以扩展实现。
protocol AccountDeletionSessionControlling: Sendable {
    func issueAppleChallenge() async throws -> PortalAppleAuthenticationChallenge
    func validAccessToken() async -> String?
    func snapshot() async -> PortalSessionSnapshot
    /// 中文注释：服务端会话已随账号删除，只清本机 Keychain 会话，不再调注销接口。
    func discardLocalSessionForDeletedAccount() async
}

/// 中文注释：本机数据按 UUID 删除；关联过的 iCloud 分区要在删除前读出，随待清 iCloud 标记保存。
protocol AccountDeletionLocalDataStoring: Sendable {
    func associatedCloudScopes(for userID: UUID) throws -> [CloudAccountScope]
    /// 中文注释：一个写事务里重置该 UUID 关联过的 iCloud 分区的同步状态与队列，再删除它的 `users` 行（其余表外键级联）。
    /// 返回事务里读出的本地书文件与封面相对路径，调用方在提交后删文件。
    func deleteLocalData(for userID: UUID) throws -> [String]
}

enum AccountDeletionCloudErasure: Equatable, Sendable {
    /// 中文注释：zone 与 `AppUserIdentity/default` 已删（或本来就不存在）。
    case erased
    /// 中文注释：当前 iCloud 承载的是别的账号，或与被删账号无关——什么都不删。
    case notOwned
}

enum AccountDeletionCloudErasureError: Error, Equatable, Sendable {
    /// 中文注释：未登录 iCloud、本 App 的 iCloud 被关或受限。
    case accountUnavailable
    /// 中文注释：断网、配额、服务暂不可用等，可以稍后重试。
    case temporarilyUnavailable
}

protocol AccountDeletionCloudDataErasing: Sendable {
    func eraseCloudData(
        for userID: UUID,
        associatedScopes: [CloudAccountScope]
    ) async throws -> AccountDeletionCloudErasure
}

/// 中文注释：未完成工作的持久化（设计第七节）。三类互不依赖，各自完成各自清。
struct AccountDeletionPendingWork: Codable, Equatable, Sendable {
    struct CloudCleanup: Codable, Equatable, Sendable {
        let userID: UUID
        let associatedScopes: [CloudAccountScope]
    }

    var inFlightUserID: UUID?
    var localCleanupUserIDs: [UUID] = []
    var localCleanupFailureCount: Int = 0
    var cloudCleanups: [CloudCleanup] = []

    var isEmpty: Bool {
        return self.inFlightUserID == nil &&
            self.localCleanupUserIDs.isEmpty &&
            self.cloudCleanups.isEmpty
    }
}

protocol AccountDeletionPendingWorkStoring: Sendable {
    func load() -> AccountDeletionPendingWork
    func save(_ work: AccountDeletionPendingWork)
}

/// 中文注释：换成新的访客身份：生成 UUID、补 `users` 行、写进 Keychain 身份存储。返回新 UUID，调用方再更新活动用户。
/// 只在 MainActor 上的删号协调器里用，不要求 Sendable（`AppUserIdentityBootstrapper` 持有非 Sendable 闭包）。
protocol GuestIdentityProvisioning {
    func provisionNewGuest() throws -> UUID
}

/// 中文注释：iCloud 归属判定（设计第 6.1 节）。云端记录不带 userID，同一个 iCloud 只承载 `AppUserIdentity/default`
/// 记着的那个账号，所以按 zone 整体判：身份记录指向被删账号 → 删；指向别的账号 → 不动；
/// 身份记录不存在 → 看本机关联证明里当前分区是否曾关联被删账号。
enum AccountDeletionCloudOwnership {
    static func isOwned(
        identityUserID: UUID?,
        deletedUserID: UUID,
        currentScope: CloudAccountScope,
        associatedScopes: [CloudAccountScope]
    ) -> Bool {
        if let identityUserID {
            return identityUserID == deletedUserID
        }
        return associatedScopes.contains(currentScope)
    }
}
