import Foundation
import GRDB

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
    var enabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(source: Source) throws {
        let encodedRule: Data = try JSONEncoder().encode(source.rule)

        self.id = source.id
        self.name = source.name
        self.baseURL = source.baseURL
        self.type = source.type.rawValue
        self.ruleJSON = String(data: encodedRule, encoding: .utf8) ?? "{}"
        self.enabled = source.enabled
        self.createdAt = source.createdAt
        self.updatedAt = source.updatedAt
    }

    /// 中文注释：domainModel 方法封装当前类型的一段业务或界面行为。
    func domainModel() throws -> Source {
        let ruleData: Data = Data(self.ruleJSON.utf8)
        let rule: SiteRule = try JSONDecoder().decode(SiteRule.self, from: ruleData)

        return Source(
            id: self.id,
            name: self.name,
            baseURL: self.baseURL,
            type: SourceType(rawValue: self.type) ?? .html,
            rule: rule,
            enabled: self.enabled,
            createdAt: self.createdAt,
            updatedAt: self.updatedAt
        )
    }
}

