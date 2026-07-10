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
        deletedAt: Date?
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
            deletedAt: self.deletedAt
        )
    }

    func sourceConfiguration() throws -> SourceConfiguration {
        let data: Data = Data(self.configJSON.utf8)
        let configuration: SourceConfiguration = try JSONDecoder().decode(SourceConfiguration.self, from: data)

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
