import Foundation

/// 中文注释：CloudKit 身份只承载 BrowseCraft 业务 UUID，不包含 Portal 或 StoreKit 凭证。
struct CloudAppUserIdentity: Hashable, Sendable {
    static let currentSchemaVersion: Int = 1

    let userID: UUID
    let schemaVersion: Int
    let createdAt: Date
    let updatedAt: Date

    init(
        userID: UUID,
        schemaVersion: Int = CloudAppUserIdentity.currentSchemaVersion,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.userID = userID
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func proposed(userID: UUID, at timestamp: Date) -> CloudAppUserIdentity {
        return CloudAppUserIdentity(
            userID: userID,
            createdAt: timestamp,
            updatedAt: timestamp
        )
    }

    var usesSupportedSchema: Bool {
        return self.schemaVersion == Self.currentSchemaVersion
    }
}

/// 中文注释：字段名集中在纯 Foundation 合同中，CloudKit Adapter 不得自行发明第二套 schema。
enum CloudAppUserIdentityRecordContract {
    static let recordType: String = "AppUserIdentity"
    static let recordName: String = "default"

    enum Field {
        static let userID: String = "userID"
        static let schemaVersion: String = "schemaVersion"
        static let createdAt: String = "createdAt"
        static let updatedAt: String = "updatedAt"
    }
}

/// 中文注释：该状态只描述用户主动关联流程；App 启动不得自动推进这些状态。
enum CloudAppUserIdentityAssociationState: Hashable, Sendable {
    case notAssociated
    case readyToCreate(localUserID: UUID)
    case associated(identity: CloudAppUserIdentity)
    case requiresUserDecision(
        localUserID: UUID,
        cloudIdentity: CloudAppUserIdentity
    )
}
