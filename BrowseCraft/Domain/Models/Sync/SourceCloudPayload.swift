import Foundation

// 中文注释：SourceCloudPayload 是站点源同步的云端载荷，先服务 mock store，后续映射到 CloudKit record。
struct SourceCloudPayload: Hashable, Codable {
    static let currentSchemaVersion: Int = 1

    var schemaVersion: Int
    var userID: String
    var sourceID: String
    var name: String
    var baseURL: String
    var type: String
    var kind: String
    var configJSON: String
    var enabled: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    var lastChangedAt: Date {
        return max(self.updatedAt, self.deletedAt ?? .distantPast)
    }

    var isDeleted: Bool {
        return self.deletedAt != nil
    }

    var isBuiltIn: Bool {
        return self.sourceID.hasPrefix("built-in.")
    }
}
