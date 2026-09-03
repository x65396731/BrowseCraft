import Foundation

struct SourceTransfer: Sendable {
    let value: Source
}

struct RulePackageExportTransfer: Sendable {
    let value: RulePackageExport
}

actor SourceRuleEditingCoordinator {
    private let service: SourceRuleEditorService

    init(service: SourceRuleEditorService) {
        self.service = service
    }

    func updateRule(
        source: SourceTransfer,
        ruleJSON: String,
        expectedUpdatedAt: Date?
    ) throws -> SourceTransfer {
        return SourceTransfer(
            value: try self.service.updateRule(
                source: source.value,
                ruleJSON: ruleJSON,
                expectedUpdatedAt: expectedUpdatedAt
            )
        )
    }

    func updateDebugJSON(
        source: SourceTransfer,
        json: String,
        expectedUpdatedAt: Date?
    ) throws -> SourceTransfer {
        return SourceTransfer(
            value: try self.service.updateDebugJSON(
                source: source.value,
                json: json,
                expectedUpdatedAt: expectedUpdatedAt
            )
        )
    }

    func duplicate(_ source: SourceTransfer) throws -> SourceTransfer {
        return SourceTransfer(value: try self.service.duplicate(source: source.value))
    }

    func export(sourceID: String) throws -> RulePackageExportTransfer {
        return RulePackageExportTransfer(value: try self.service.exportPackage(sourceID: sourceID))
    }

    func importPackage(_ packageJSON: String) throws -> SourceTransfer {
        return SourceTransfer(value: try self.service.importPackage(packageJSON: packageJSON))
    }
}
