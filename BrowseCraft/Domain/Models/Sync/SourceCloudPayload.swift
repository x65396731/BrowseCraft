import Foundation
import BrowseCraftCore

// 中文注释：SourceCloudPayload 是站点源同步的云端载荷，先服务 mock store，后续映射到 CloudKit record。
struct SourceCloudPayload: Hashable, Codable, Sendable {
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

    /// 中文注释：P2-6 后云端旧 V1 video payload 不能重新写回本地数据库。
    var isUnsupportedVideoV1: Bool {
        guard self.kind == SourceRuntimeKind.video.rawValue,
              let data: Data = self.configJSON.data(using: .utf8),
              let root: [String: Any] = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let video: [String: Any] = root["video"] as? [String: Any] else {
            return self.kind == SourceRuntimeKind.video.rawValue
        }
        return video["strategy"] as? String != VideoSourceConfiguration.strategy
    }
}
