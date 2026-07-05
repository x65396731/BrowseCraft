import Foundation
import GRDB

// 中文注释：SourceRecord 是 Source 在 SQLite 中的持久化形态。

/// 中文注释：数据库记录留在基础设施层，领域模型不直接依赖 GRDB。
struct SourceRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName: String = "sources"

    var id: String
    var name: String
    var baseURL: String
    var type: String
    var kind: String
    var configJSON: String
    var enabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(source: Source) throws {
        let encodedConfiguration: Data = try JSONEncoder().encode(source.configuration)

        self.id = source.id
        self.name = source.name
        self.baseURL = source.baseURL
        self.type = source.type.rawValue
        self.kind = source.configuration.kind.rawValue
        self.configJSON = String(data: encodedConfiguration, encoding: .utf8) ?? "{}"
        self.enabled = source.enabled
        self.createdAt = source.createdAt
        self.updatedAt = source.updatedAt
    }

    func domainModel() throws -> Source {
        return Source(
            id: self.id,
            name: self.name,
            baseURL: self.baseURL,
            type: SourceType(rawValue: self.type) ?? .html,
            configuration: try self.sourceConfiguration(),
            enabled: self.enabled,
            createdAt: self.createdAt,
            updatedAt: self.updatedAt
        )
    }

    private func sourceConfiguration() throws -> SourceConfiguration {
        let data: Data = Data(self.configJSON.utf8)
        let configuration: SourceConfiguration = try JSONDecoder().decode(SourceConfiguration.self, from: data)

        guard configuration.kind.rawValue == self.kind else {
            throw SourceRecordDecodingError.mismatchedConfigurationKind
        }

        return configuration
    }
}

enum SourceRecordDecodingError: Error {
    case mismatchedConfigurationKind
}
