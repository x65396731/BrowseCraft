import BrowseCraftCore
import BrowseCraftDomain
import Foundation
import GRDB

// 中文注释：SourceRecord 是 Source 在 SQLite 中的持久化形态。

/// 中文注释：数据库记录留在基础设施层，领域模型不直接依赖 GRDB。
struct SourceRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName: String = "sources"

    var userID: String
    var id: String
    var name: String
    var baseURL: String
    var type: String
    var kind: String
    var configJSON: String
    var enabled: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    /// 中文注释：`SourceOrigin.rawValue`；v2 迁移新增列，旧行为 NULL。
    var origin: String?

    init(
        userID: String,
        id: String,
        name: String,
        baseURL: String,
        type: String,
        kind: String,
        configJSON: String,
        enabled: Bool,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        origin: String? = nil
    ) {
        self.userID = userID
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.type = type
        self.kind = kind
        self.configJSON = configJSON
        self.enabled = enabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.origin = origin
    }

    init(source: Source) throws {
        let encodedConfiguration: Data = try JSONEncoder().encode(source.configuration)

        self.userID = source.userID
        self.id = source.id
        self.name = source.name
        self.baseURL = source.baseURL
        self.type = source.type.rawValue
        self.kind = source.configuration.kind.rawValue
        self.configJSON = String(data: encodedConfiguration, encoding: .utf8) ?? "{}"
        self.enabled = source.enabled
        self.createdAt = source.createdAt
        self.updatedAt = source.updatedAt
        self.deletedAt = source.deletedAt
        self.origin = source.origin?.rawValue
    }

    func domainModel() throws -> Source {
        return Source(
            userID: self.userID,
            id: self.id,
            name: self.name,
            baseURL: self.baseURL,
            type: SourceType(rawValue: self.type) ?? .html,
            configuration: try self.sourceConfiguration(),
            enabled: self.enabled,
            createdAt: self.createdAt,
            updatedAt: self.updatedAt,
            deletedAt: self.deletedAt,
            origin: self.origin.flatMap(SourceOrigin.init(rawValue:))
        )
    }

    func sourceConfiguration() throws -> SourceConfiguration {
        // 中文注释：同一条记录的 configJSON 在多次读取之间通常不变（每次进列表、历史、收藏都要解一遍全部来源），
        // 按「用户 + id」缓存解码结果并用 JSON 原文比对命中，避免重复 JSONDecoder。
        let configuration: SourceConfiguration = try SourceConfigurationDecodingCache.shared.configuration(
            userID: self.userID,
            sourceID: self.id,
            configJSON: self.configJSON
        )

        guard self.matchesStoredKind(configuration.kind) else {
            throw SourceRecordDecodingError.mismatchedConfigurationKind
        }

        return configuration
    }

    private func matchesStoredKind(_ runtimeKind: SourceRuntimeKind) -> Bool {
        if runtimeKind.rawValue == self.kind {
            return true
        }

        return runtimeKind == .comic && self.kind == "rule"
    }

    var lastChangedAt: Date {
        return max(self.updatedAt, self.deletedAt ?? .distantPast)
    }
}

enum SourceRecordDecodingError: Error {
    case mismatchedConfigurationKind
}

/// 中文注释：SourceConfiguration 的解码缓存。键是用户 + 来源 id，命中条件是 JSON 原文逐字相等
/// （字符串比较远比解码便宜，也不会像哈希那样有碰撞风险）；有界，超限整体清空。
final class SourceConfigurationDecodingCache: @unchecked Sendable {
    static let shared: SourceConfigurationDecodingCache = SourceConfigurationDecodingCache()

    private struct Entry {
        let configJSON: String
        let configuration: SourceConfiguration
    }

    private let lock: NSLock = NSLock()
    private var entries: [String: Entry] = [:]
    private let entryLimit: Int

    init(entryLimit: Int = 256) {
        self.entryLimit = max(1, entryLimit)
    }

    func configuration(userID: String, sourceID: String, configJSON: String) throws -> SourceConfiguration {
        let key: String = "\(userID)\u{1F}\(sourceID)"
        if let cached: Entry = self.lock.withLock({ self.entries[key] }), cached.configJSON == configJSON {
            return cached.configuration
        }
        let decoded: SourceConfiguration = try JSONDecoder().decode(SourceConfiguration.self, from: Data(configJSON.utf8))
        self.lock.withLock {
            if self.entries.count >= self.entryLimit {
                self.entries.removeAll(keepingCapacity: true)
            }
            self.entries[key] = Entry(configJSON: configJSON, configuration: decoded)
        }
        return decoded
    }

    func removeAll() {
        self.lock.withLock { self.entries.removeAll() }
    }
}
