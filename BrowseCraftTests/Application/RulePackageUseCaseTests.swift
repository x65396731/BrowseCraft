import Foundation
import Testing
@testable import BrowseCraft

// 中文注释：P2-2 规则包测试，覆盖 BrowseCraft 自有导入/导出 envelope 与 checksum 边界。
struct RulePackageUseCaseTests {
    @Test func exportUseCaseBuildsPackageFromLatestSource() throws {
        let repository: RulePackageInMemorySourceRepository = RulePackageInMemorySourceRepository()
        let source: Source = try Self.source(
            id: "user-rule",
            name: "Export / Source",
            baseURL: "https://source.example"
        )
        try repository.saveSource(source)
        let coder: RulePackageCoder = RulePackageCoder(
            now: {
                return Date(timeIntervalSince1970: 1_234)
            }
        )
        let useCase: ExportSourceRulePackageUseCase = ExportSourceRulePackageUseCase(
            sourceRepository: repository,
            coder: coder,
            appVersion: "1.0-test"
        )

        let export: RulePackageExport = try useCase.execute(sourceID: "user-rule")
        let package: BrowseCraftRulePackage = try coder.decodePackage(packageJSON: export.packageJSON)

        #expect(export.suggestedFileName == "Export-Source.browsecraft-rule.json")
        #expect(package.metadata.sourceID == "user-rule")
        #expect(package.metadata.sourceName == "Export / Source")
        #expect(package.metadata.sourceBaseURL == "https://source.example")
        #expect(package.metadata.ruleName == "Complete V2 Site")
        #expect(package.metadata.appVersion == "1.0-test")
        #expect(package.rule == source.rule)
    }

    @Test func exportUseCaseRejectsMissingSource() throws {
        let repository: RulePackageInMemorySourceRepository = RulePackageInMemorySourceRepository()
        let useCase: ExportSourceRulePackageUseCase = ExportSourceRulePackageUseCase(
            sourceRepository: repository
        )

        do {
            _ = try useCase.execute(sourceID: "missing-source")
            Issue.record("Expected missing source export to fail.")
        } catch RulePackageError.sourceNotFound {
            #expect(true)
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }
    }

    @Test func exportUseCaseAllowsBuiltInSourcePackage() throws {
        let repository: RulePackageInMemorySourceRepository = RulePackageInMemorySourceRepository()
        let builtInSource: Source = try Self.source(
            id: "built-in.complete-v2",
            name: "Built In Source",
            baseURL: "https://built-in.example"
        )
        try repository.saveSource(builtInSource)
        let coder: RulePackageCoder = RulePackageCoder(
            now: {
                return Date(timeIntervalSince1970: 1_234)
            }
        )
        let useCase: ExportSourceRulePackageUseCase = ExportSourceRulePackageUseCase(
            sourceRepository: repository,
            coder: coder
        )

        let export: RulePackageExport = try useCase.execute(sourceID: "built-in.complete-v2")
        let package: BrowseCraftRulePackage = try coder.decodePackage(packageJSON: export.packageJSON)

        #expect(package.metadata.sourceID == "built-in.complete-v2")
        #expect(package.metadata.sourceName == "Built In Source")
        #expect(package.metadata.sourceBaseURL == "https://built-in.example")
        #expect(package.rule == builtInSource.rule)
    }

    @Test func importUseCaseSavesRulePackageAsUserSource() throws {
        let repository: RulePackageInMemorySourceRepository = RulePackageInMemorySourceRepository()
        let rule: SiteRule = try Self.completeV2Rule()
        let coder: RulePackageCoder = RulePackageCoder(
            now: {
                return Date(timeIntervalSince1970: 1_234)
            }
        )
        let packageJSON: String = try coder.encodePackage(
            rule: rule,
            sourceID: "remote-user-rule",
            sourceName: "Remote Source",
            sourceBaseURL: "https://remote.example",
            appVersion: "1.0-test"
        )
        let useCase: ImportSourceRulePackageUseCase = ImportSourceRulePackageUseCase(
            sourceRepository: repository,
            coder: coder,
            now: {
                return Date(timeIntervalSince1970: 2_000)
            },
            idGenerator: {
                return "generated-import-id"
            }
        )

        let importedSource: Source = try useCase.execute(packageJSON: packageJSON)

        #expect(importedSource.id == "remote-user-rule")
        #expect(importedSource.name == "Remote Source")
        #expect(importedSource.baseURL == "https://remote.example")
        #expect(importedSource.type == .html)
        #expect(importedSource.rule == rule)
        #expect(importedSource.isBuiltIn == false)
        #expect(importedSource.createdAt == Date(timeIntervalSince1970: 2_000))
        #expect(repository.savedSources["remote-user-rule"] == importedSource)
    }

    @Test func importUseCaseDoesNotOverwriteExistingSourceID() throws {
        let repository: RulePackageInMemorySourceRepository = RulePackageInMemorySourceRepository()
        let existingSource: Source = try Self.source(
            id: "remote-user-rule",
            name: "Existing Source",
            baseURL: "https://existing.example"
        )
        try repository.saveSource(existingSource)
        let rule: SiteRule = try Self.completeV2Rule()
        let coder: RulePackageCoder = RulePackageCoder(
            now: {
                return Date(timeIntervalSince1970: 1_234)
            }
        )
        let packageJSON: String = try coder.encodePackage(
            rule: rule,
            sourceID: "remote-user-rule",
            sourceName: "Imported Source",
            sourceBaseURL: "https://imported.example"
        )
        let useCase: ImportSourceRulePackageUseCase = ImportSourceRulePackageUseCase(
            sourceRepository: repository,
            coder: coder,
            idGenerator: {
                return "generated-import-id"
            }
        )

        let importedSource: Source = try useCase.execute(packageJSON: packageJSON)

        #expect(importedSource.id == "generated-import-id")
        #expect(repository.savedSources["remote-user-rule"] == existingSource)
        #expect(repository.savedSources["generated-import-id"] == importedSource)
    }

    @Test func importUseCaseDoesNotOverwriteBuiltInSourceID() throws {
        let repository: RulePackageInMemorySourceRepository = RulePackageInMemorySourceRepository()
        let builtInSource: Source = try Self.source(
            id: "built-in.complete-v2",
            name: "Built In Source",
            baseURL: "https://built-in.example"
        )
        try repository.saveSource(builtInSource)
        let coder: RulePackageCoder = RulePackageCoder(
            now: {
                return Date(timeIntervalSince1970: 1_234)
            }
        )
        let exportUseCase: ExportSourceRulePackageUseCase = ExportSourceRulePackageUseCase(
            sourceRepository: repository,
            coder: coder
        )
        let importUseCase: ImportSourceRulePackageUseCase = ImportSourceRulePackageUseCase(
            sourceRepository: repository,
            coder: coder,
            idGenerator: {
                return "generated-user-copy"
            }
        )

        let export: RulePackageExport = try exportUseCase.execute(sourceID: "built-in.complete-v2")
        let importedSource: Source = try importUseCase.execute(packageJSON: export.packageJSON)

        #expect(importedSource.id == "generated-user-copy")
        #expect(importedSource.isBuiltIn == false)
        #expect(repository.savedSources["built-in.complete-v2"] == builtInSource)
        #expect(repository.savedSources["generated-user-copy"] == importedSource)
    }

    private static func completeV2Rule() throws -> SiteRule {
        return try JSONDecoder().decode(
            SiteRule.self,
            from: Data(RuleJSONFixtures.completeV2SiteRule.utf8)
        )
    }

    private static func source(id: String, name: String, baseURL: String) throws -> Source {
        let rule: SiteRule = try self.completeV2Rule()
        let now: Date = Date(timeIntervalSince1970: 1_000)

        return Source(
            id: id,
            name: name,
            baseURL: baseURL,
            type: .html,
            rule: rule,
            enabled: true,
            createdAt: now,
            updatedAt: now
        )
    }
}

private final class RulePackageInMemorySourceRepository: SourceRepository {
    var savedSources: [String: Source] = [:]

    func fetchSources() throws -> [Source] {
        return Array(self.savedSources.values)
    }

    func saveSource(_ source: Source) throws {
        self.savedSources[source.id] = source
    }

    func deleteSource(id: String) throws {
        self.savedSources.removeValue(forKey: id)
    }
}
