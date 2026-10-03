import Foundation

// 中文注释：续看位置同步（`docs/design/History-Resume-Sync-Design.md`）：每部作品一条精简记录，
// 只带「看到哪里」，不带整行历史——会过期的播放地址、请求配置、缓存键与规则快照都不上云（`BCA-SYNC-009`）。

enum HistoryEntryKind: String, Codable, Hashable, Sendable, CaseIterable {
    case comic
    case video
    case book
}

/// 中文注释：一部作品的同步身份。`kind` 留字符串：更新版本才有的类型在下行时逐条跳过，不拖垮整批。
struct HistoryEntryIdentity: Hashable, Codable, Sendable {
    let kind: String
    let sourceID: String
    /// 中文注释：漫画是条目 ID，视频是作品键（`vod::` / `detail::` / `title::`），站点书是详情地址。
    let workKey: String

    init(kind: String, sourceID: String, workKey: String) {
        self.kind = kind
        self.sourceID = sourceID
        self.workKey = workKey
    }

    /// 中文注释：同步队列需要可逆键；三段都可能含任意字符，用 JSON 数组编码。
    var syncEntityID: String {
        let components: [String] = [self.kind, self.sourceID, self.workKey]
        guard let data: Data = try? JSONEncoder().encode(components),
              let text: String = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }

    init?(syncEntityID: String) {
        guard let data: Data = syncEntityID.data(using: .utf8),
              let components: [String] = try? JSONDecoder().decode([String].self, from: data),
              components.count == 3 else {
            return nil
        }
        self.init(kind: components[0], sourceID: components[1], workKey: components[2])
    }
}

/// 中文注释：云端 `HistoryEntry` 记录的载荷；哪种内容用哪些字段见设计第二节。
struct HistoryEntryCloudPayload: Hashable, Codable, Sendable {
    static let currentSchemaVersion: Int = 1

    var schemaVersion: Int
    var kind: String
    var sourceID: String
    var workKey: String
    var itemID: String?
    var title: String?
    var coverURL: String?
    var detailURL: String?
    var unitKey: String?
    var unitTitle: String?
    var unitURL: String?
    var pageIndex: Int?
    var sourceIndex: Int?
    var episodeIndex: Int?
    var playbackTime: Double?
    var duration: Double?
    var locatorJSON: String?
    var totalProgression: Double?
    var visitedAt: Date?
    var updatedAt: Date
    var deletedAt: Date?

    var identity: HistoryEntryIdentity {
        return HistoryEntryIdentity(kind: self.kind, sourceID: self.sourceID, workKey: self.workKey)
    }

    var lastChangedAt: Date {
        return max(self.updatedAt, self.deletedAt ?? .distantPast)
    }

    var isDeleted: Bool {
        return self.deletedAt != nil
    }

    /// 中文注释：删除标记只带身份与时间。
    static func tombstone(identity: HistoryEntryIdentity, deletedAt: Date) -> HistoryEntryCloudPayload {
        return HistoryEntryCloudPayload(
            schemaVersion: Self.currentSchemaVersion,
            kind: identity.kind,
            sourceID: identity.sourceID,
            workKey: identity.workKey,
            updatedAt: deletedAt,
            deletedAt: deletedAt
        )
    }
}
