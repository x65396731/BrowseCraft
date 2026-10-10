import BrowseCraftDomain
import Foundation

// 中文注释：SourceSnapshot 保存脱离 sources 表后仍可恢复运行所需的来源配置快照。
// 只有 App（历史与同步）用它，2026-10-10 从 BrowseCraftDomain 搬回。
struct SourceSnapshot: Hashable, Codable, Sendable {
    var userID: String?
    var id: String
    var name: String
    var baseURL: String
    var type: SourceType
    var configuration: SourceConfiguration
    var enabled: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(source: Source) {
        self.userID = source.userID
        self.id = source.id
        self.name = source.name
        self.baseURL = source.baseURL
        self.type = source.type
        self.configuration = source.configuration
        self.enabled = source.enabled
        self.createdAt = source.createdAt
        self.updatedAt = source.updatedAt
        self.deletedAt = source.deletedAt
    }

    func source() -> Source {
        return Source(
            userID: self.userID ?? AppUserIdentity.localDefaultID,
            id: self.id,
            name: self.name,
            baseURL: self.baseURL,
            type: self.type,
            configuration: self.configuration,
            enabled: self.enabled,
            createdAt: self.createdAt,
            updatedAt: self.updatedAt,
            deletedAt: self.deletedAt
        )
    }
}
