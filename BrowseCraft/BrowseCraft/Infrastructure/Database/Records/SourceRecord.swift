import Foundation
import GRDB

/// GRDB representation of Source.
///
/// Records stay in Infrastructure. Domain models stay clean and do not conform
/// to GRDB protocols.
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

