import Foundation
import GRDB
import BrowseCraftCore

// 中文注释：SourceRecord.swift 属于数据库记录映射层，用于说明本文件承载的核心职责。

/// 中文注释：Source 在 GRDB 中的数据库记录表示。
/// 中文注释：数据库记录留在基础设施层，领域模型不直接遵循 GRDB 协议。
struct SourceRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName: String = "sources"

    var id: String
    var name: String
    var baseURL: String
    var type: String
    var ruleJSON: String
    var kind: String?
    var configJSON: String?
    var enabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(source: Source) throws {
        let encodedRule: Data
        if let rule: SiteRule = source.ruleConfiguration?.rule {
            encodedRule = try JSONEncoder().encode(rule)
        } else {
            encodedRule = Data("{}".utf8)
        }
        let encodedConfiguration: Data = try JSONEncoder().encode(source.configuration)

        self.id = source.id
        self.name = source.name
        self.baseURL = source.baseURL
        self.type = source.type.rawValue
        self.ruleJSON = String(data: encodedRule, encoding: .utf8) ?? "{}"
        self.kind = source.configuration.kind.rawValue
        self.configJSON = String(data: encodedConfiguration, encoding: .utf8) ?? self.ruleJSON
        self.enabled = source.enabled
        self.createdAt = source.createdAt
        self.updatedAt = source.updatedAt
    }

    /// 中文注释：domainModel 方法封装当前类型的一段业务或界面行为。
    func domainModel() throws -> Source {
        let configuration: SourceConfiguration = try self.sourceConfiguration()
        return Source(
            id: self.id,
            name: self.name,
            baseURL: self.baseURL,
            type: SourceType(rawValue: self.type) ?? .html,
            configuration: configuration,
            enabled: self.enabled,
            createdAt: self.createdAt,
            updatedAt: self.updatedAt
        )
    }

    func sourceConfiguration() throws -> SourceConfiguration {
        let decoder: JSONDecoder = JSONDecoder()
        let sourceKind: SourceDefinitionKind = SourceDefinitionKind(rawValue: self.kind ?? "") ?? .rule

        if let configJSON: String = self.configJSON, configJSON.isEmpty == false {
            let configData: Data = Data(configJSON.utf8)
            if let configuration: SourceConfiguration = try? decoder.decode(SourceConfiguration.self, from: configData) {
                guard configuration.kind == sourceKind else {
                    throw SourceRecordDecodingError.mismatchedConfigurationKind
                }

                return configuration
            }

            if sourceKind == .rule {
                return .rule(try self.decodeRuleConfiguration(using: decoder, data: configData))
            }

            throw SourceRecordDecodingError.mismatchedConfigurationKind
        }

        guard sourceKind == .rule else {
            throw SourceRecordDecodingError.missingConfiguration(sourceKind.rawValue)
        }

        return .rule(try self.decodeLegacyRuleConfiguration(using: decoder))
    }

    private func decodeRuleConfiguration(using decoder: JSONDecoder, data: Data) throws -> RuleSourceConfiguration {
        let rule: SiteRule = try decoder.decode(SiteRule.self, from: data)
        return RuleSourceConfiguration(
            rule: rule,
            schemaVersion: rule.version ?? 1,
            packageMetadata: nil,
            isEditable: self.id.hasPrefix("built-in.") == false
        )
    }

    private func decodeLegacyRuleConfiguration(using decoder: JSONDecoder) throws -> RuleSourceConfiguration {
        let ruleData: Data = Data(self.ruleJSON.utf8)
        return try self.decodeRuleConfiguration(using: decoder, data: ruleData)
    }
}

enum SourceRecordDecodingError: Error {
    case mismatchedConfigurationKind
    case missingConfiguration(String)
}
