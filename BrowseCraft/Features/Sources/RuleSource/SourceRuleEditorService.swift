import BrowseCraftCore
import BrowseCraftRulesKit
import Foundation

struct SourceDebugJSONValidationResult: Hashable {
    var isValid: Bool
    var message: String
}

enum SourceRuleEditorServiceError: LocalizedError {
    case readOnlySource

    var errorDescription: String? {
        switch self {
        case .readOnlySource:
            return "This source JSON is read-only."
        }
    }
}

struct SourceRuleEditorService {
    private let updateSourceRuleUseCase: UpdateSourceRuleUseCase
    private let updateVideoSourceConfigurationUseCase: UpdateVideoSourceConfigurationUseCase
    private let duplicateSourceRuleUseCase: DuplicateSourceRuleUseCase
    private let exportSourceRulePackageUseCase: ExportSourceRulePackageUseCase
    private let importSourceRulePackageUseCase: ImportSourceRulePackageUseCase
    private let ruleValidator: SiteRuleValidator
    private let jsonEncoder: JSONEncoder

    init(
        updateSourceRuleUseCase: UpdateSourceRuleUseCase,
        updateVideoSourceConfigurationUseCase: UpdateVideoSourceConfigurationUseCase,
        duplicateSourceRuleUseCase: DuplicateSourceRuleUseCase,
        exportSourceRulePackageUseCase: ExportSourceRulePackageUseCase,
        importSourceRulePackageUseCase: ImportSourceRulePackageUseCase,
        ruleValidator: SiteRuleValidator = SiteRuleValidator(),
        jsonEncoder: JSONEncoder = JSONEncoder()
    ) {
        self.updateSourceRuleUseCase = updateSourceRuleUseCase
        self.updateVideoSourceConfigurationUseCase = updateVideoSourceConfigurationUseCase
        self.duplicateSourceRuleUseCase = duplicateSourceRuleUseCase
        self.exportSourceRulePackageUseCase = exportSourceRulePackageUseCase
        self.importSourceRulePackageUseCase = importSourceRulePackageUseCase
        self.ruleValidator = ruleValidator
        self.jsonEncoder = jsonEncoder
        self.jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    }

    func validateRuleJSON(_ ruleJSON: String) -> SiteRuleValidationResult {
        return self.ruleValidator.validate(ruleJSON: ruleJSON)
    }

    func formattedRuleJSON(for rule: SiteRule) -> String {
        return (try? self.formattedJSON(rule)) ?? "{}"
    }

    func formattedDebugJSON(for source: Source) -> String {
        do {
            switch source.configuration {
            case .comic(let configuration):
                return try self.formattedJSON(configuration.rule)
            case .video(let configuration):
                return try self.formattedJSON(configuration)
            case .rss(let configuration):
                return try self.formattedJSON(configuration)
            case .plugin(let configuration):
                return try self.formattedJSON(configuration)
            }
        } catch {
            return "{}"
        }
    }

    func canEditDebugJSON(for source: Source) -> Bool {
        guard source.isBuiltIn == false else {
            return false
        }

        switch source.configuration {
        case .comic, .video:
            return true
        case .rss, .plugin:
            return false
        }
    }

    func validateDebugJSON(source: Source, json: String) -> SourceDebugJSONValidationResult {
        switch source.configuration {
        case .comic:
            let validationResult: SiteRuleValidationResult = self.validateRuleJSON(json)
            if validationResult.canSave {
                return SourceDebugJSONValidationResult(isValid: true, message: "Rule JSON is valid.")
            }

            return SourceDebugJSONValidationResult(
                isValid: false,
                message: validationResult.errors.first?.message ?? "Rule JSON is invalid."
            )
        case .video:
            do {
                try self.updateVideoSourceConfigurationUseCase.validate(configurationJSON: json)
                return SourceDebugJSONValidationResult(
                    isValid: true,
                    message: "Video configuration JSON is valid."
                )
            } catch {
                return SourceDebugJSONValidationResult(isValid: false, message: error.localizedDescription)
            }
        case .rss:
            return SourceDebugJSONValidationResult(isValid: false, message: "RSS JSON is read-only.")
        case .plugin:
            return SourceDebugJSONValidationResult(isValid: false, message: "Plugin JSON is read-only.")
        }
    }

    func updateRule(
        source: Source,
        ruleJSON: String,
        expectedUpdatedAt: Date?
    ) throws -> Source {
        return try self.updateSourceRuleUseCase.execute(
            source: source,
            ruleJSON: ruleJSON,
            expectedUpdatedAt: expectedUpdatedAt
        )
    }

    func updateDebugJSON(
        source: Source,
        json: String,
        expectedUpdatedAt: Date?
    ) throws -> Source {
        switch source.configuration {
        case .comic:
            return try self.updateRule(
                source: source,
                ruleJSON: json,
                expectedUpdatedAt: expectedUpdatedAt
            )
        case .video:
            return try self.updateVideoSourceConfigurationUseCase.execute(
                source: source,
                configurationJSON: json,
                expectedUpdatedAt: expectedUpdatedAt
            )
        case .rss, .plugin:
            throw SourceRuleEditorServiceError.readOnlySource
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
