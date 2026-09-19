import BrowseCraftCore
import BrowseCraftDomain
import Foundation

struct SourceRuleEditorService: Sendable {
    private let duplicateSourceRuleUseCase: DuplicateSourceRuleUseCase
    private let exportSourceRulePackageUseCase: ExportSourceRulePackageUseCase
    private let importSourceRulePackageUseCase: ImportSourceRulePackageUseCase
    private let ruleValidator: SiteRuleValidator
    private let jsonEncoder: JSONEncoder

    init(
        duplicateSourceRuleUseCase: DuplicateSourceRuleUseCase,
        exportSourceRulePackageUseCase: ExportSourceRulePackageUseCase,
        importSourceRulePackageUseCase: ImportSourceRulePackageUseCase,
        ruleValidator: SiteRuleValidator = SiteRuleValidator(),
        jsonEncoder: JSONEncoder = JSONEncoder()
    ) {
        self.duplicateSourceRuleUseCase = duplicateSourceRuleUseCase
        self.exportSourceRulePackageUseCase = exportSourceRulePackageUseCase
        self.importSourceRulePackageUseCase = importSourceRulePackageUseCase
        self.ruleValidator = ruleValidator
        self.jsonEncoder = jsonEncoder
        self.jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    }

    func formattedDebugJSON(for source: Source) -> String {
        do {
            switch source.configuration {
            case .comic(let configuration):
                return try self.formattedJSON(configuration.rule)
            case .video(let configuration):
                return try self.formattedJSON(configuration)
            case .plugin(let configuration):
                return try self.formattedJSON(configuration)
            case .book(let configuration):
                return try self.formattedJSON(configuration.rule)
            }
        } catch {
            return "{}"
        }
    }

    func duplicate(source: Source) throws -> Source {
        return try self.duplicateSourceRuleUseCase.execute(source: source)
    }

    func exportPackage(sourceID: String) throws -> RulePackageExport {
        return try self.exportSourceRulePackageUseCase.execute(sourceID: sourceID)
    }

    func importPackage(packageJSON: String) throws -> Source {
        return try self.importSourceRulePackageUseCase.execute(packageJSON: packageJSON)
    }

    private func formattedJSON<Value: Encodable>(_ value: Value) throws -> String {
        let encodedValue: Data = try self.jsonEncoder.encode(value)
        return String(data: encodedValue, encoding: .utf8) ?? "{}"
    }
}
