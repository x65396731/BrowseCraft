import Foundation
import Testing
@testable import BrowseCraft

// 中文注释：P2-1 规则管理测试，覆盖 JSON 校验、内置只读、用户规则保存和复制边界。
struct RuleManagementUseCaseTests {
    @Test func validatorAcceptsCompleteV2Rule() throws {
        let validator: RuleValidator = RuleValidator()

        let result: RuleValidationResult = validator.validate(ruleJSON: RuleJSONFixtures.completeV2SiteRule)

        #expect(result.canSave)
        #expect(result.errors.isEmpty)
        #expect(result.rule?.name == "Complete V2 Site")
    }

    @Test func validatorRejectsMissingReferencedRule() throws {
        let invalidRuleJSON: String = RuleJSONFixtures.completeV2SiteRule.replacingOccurrences(
            of: "\"list\": \"home-list\"",
            with: "\"list\": \"missing-list\""
        )
        let validator: RuleValidator = RuleValidator()

        let result: RuleValidationResult = validator.validate(ruleJSON: invalidRuleJSON)

        #expect(result.canSave == false)
        #expect(result.errors.contains { issue in
            return issue.message.contains("missing-list")
        })
    }

    @Test func validatorRejectsDuplicatePageIDs() throws {
        var rule: SiteRule = try Self.completeV2Rule()
        rule.pages?[1].id = "home"
        let validator: RuleValidator = RuleValidator()

        let result: RuleValidationResult = validator.validate(rule: rule)

        #expect(result.canSave == false)
        #expect(result.errors.contains { issue in
            return issue.id == "page-id-duplicate-home"
        })
    }

    @Test func validatorRejectsRuleRefsWithoutRuleSets() throws {
        var rule: SiteRule = try Self.completeV2Rule()
        rule.ruleSets = nil
        let validator: RuleValidator = RuleValidator()

        let result: RuleValidationResult = validator.validate(rule: rule)

        #expect(result.canSave == false)
        #expect(result.errors.contains { issue in
            return issue.id == "rule-sets-missing"
        })
    }

    @Test func validatorRejectsDuplicateRuleSetIDs() throws {
        var rule: SiteRule = try Self.completeV2Rule()
        let duplicatedListRule: ListRule = try #require(rule.ruleSets?.listRules?.first)
        rule.ruleSets?.listRules?.append(duplicatedListRule)
        let validator: RuleValidator = RuleValidator()

        let result: RuleValidationResult = validator.validate(rule: rule)

        #expect(result.canSave == false)
        #expect(result.errors.contains { issue in
            return issue.id == "rule-id-duplicate-list-home-list"
        })
    }

    @Test func validatorWarnsWhenPageBasicsAreIncomplete() throws {
        var rule: SiteRule = try Self.completeV2Rule()
        rule.pages?[0].title = ""
        rule.pages?[0].ruleRefs?.list = nil
        let validator: RuleValidator = RuleValidator()

        let result: RuleValidationResult = validator.validate(rule: rule)

        #expect(result.canSave)
        #expect(result.warnings.contains { issue in
            return issue.id == "page-title-empty-home"
        })
        #expect(result.warnings.contains { issue in
            return issue.id == "page-list-ref-empty-home"
        })
    }

    @Test func updateSourceRuleRejectsBuiltInSource() throws {
        let repository: InMemorySourceRepository = InMemorySourceRepository()
        let source: Source = try Self.source(id: "built-in.example")
        try repository.saveSource(source)
        let useCase: UpdateSourceRuleUseCase = UpdateSourceRuleUseCase(sourceRepository: repository)

        #expect(throws: RuleManagementError.self) {
            _ = try useCase.execute(source: source, ruleJSON: RuleJSONFixtures.completeV2SiteRule)
        }
    }

    @Test func updateSourceRuleSavesUserRuleWhenValidationPasses() throws {
        let repository: InMemorySourceRepository = InMemorySourceRepository()
        let source: Source = try Self.source(
            id: "user-rule",
            ruleJSON: Self.minimalEditableV2RuleJSON(
                name: "Editable V2 Site",
                baseURL: "https://editable.example"
            )
        )
        try repository.saveSource(source)
        let updatedRuleJSON: String = Self.minimalEditableV2RuleJSON(
            name: "Updated V2 Site",
            baseURL: "https://updated.example"
        )
        let useCase: UpdateSourceRuleUseCase = UpdateSourceRuleUseCase(sourceRepository: repository)

        let updatedSource: Source = try useCase.execute(source: source, ruleJSON: updatedRuleJSON)

        #expect(updatedSource.id == "user-rule")
        #expect(updatedSource.name == "Updated V2 Site")
        #expect(updatedSource.baseURL == "https://updated.example")
        #expect(updatedSource.updatedAt > source.updatedAt)
        #expect(repository.savedSources["user-rule"]?.rule.name == "Updated V2 Site")
        #expect(repository.savedSources["user-rule"]?.baseURL == "https://updated.example")
    }

    @Test func updateSourceRuleRejectsStaleDraftVersion() throws {
        let repository: InMemorySourceRepository = InMemorySourceRepository()
        let source: Source = try Self.source(
            id: "user-rule",
            ruleJSON: Self.minimalEditableV2RuleJSON(
                name: "Editable V2 Site",
                baseURL: "https://editable.example"
            )
        )
        var changedSource: Source = source
        changedSource.updatedAt = Date(timeIntervalSince1970: 2_000)
        try repository.saveSource(changedSource)
        let updatedRuleJSON: String = Self.minimalEditableV2RuleJSON(
            name: "Updated V2 Site",
            baseURL: "https://updated.example"
        )
        let useCase: UpdateSourceRuleUseCase = UpdateSourceRuleUseCase(sourceRepository: repository)

        do {
            _ = try useCase.execute(
                source: source,
                ruleJSON: updatedRuleJSON,
                expectedUpdatedAt: source.updatedAt
            )
            Issue.record("Expected stale draft update to fail.")
        } catch RuleManagementError.sourceChanged {
            #expect(repository.savedSources["user-rule"]?.name == "Editable V2 Site")
            #expect(repository.savedSources["user-rule"]?.baseURL == "https://editable.example")
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }
    }

    @Test func duplicateSourceCreatesEditableUserRule() throws {
        let repository: InMemorySourceRepository = InMemorySourceRepository()
        let source: Source = try Self.source(id: "built-in.example")
        let useCase: DuplicateSourceRuleUseCase = DuplicateSourceRuleUseCase(sourceRepository: repository)

        let duplicatedSource: Source = try useCase.execute(source: source)

        #expect(duplicatedSource.id.hasPrefix("built-in.") == false)
        #expect(duplicatedSource.isBuiltIn == false)
        #expect(duplicatedSource.name == "Complete V2 Site Copy")
        #expect(duplicatedSource.rule == source.rule)
        #expect(repository.savedSources[duplicatedSource.id] == duplicatedSource)
    }

    private static func source(id: String) throws -> Source {
        return try self.source(id: id, ruleJSON: RuleJSONFixtures.completeV2SiteRule)
    }

    private static func completeV2Rule() throws -> SiteRule {
        return try JSONDecoder().decode(
            SiteRule.self,
            from: Data(RuleJSONFixtures.completeV2SiteRule.utf8)
        )
    }

    private static func source(id: String, ruleJSON: String) throws -> Source {
        let rule: SiteRule = try JSONDecoder().decode(
            SiteRule.self,
            from: Data(ruleJSON.utf8)
        )
        let now: Date = Date(timeIntervalSince1970: 1_000)

        return Source(
            id: id,
            name: rule.name,
            baseURL: rule.baseUrl,
            type: .html,
            rule: rule,
            enabled: true,
            createdAt: now,
            updatedAt: now
        )
    }

    private static func minimalEditableV2RuleJSON(name: String, baseURL: String) -> String {
        return """
        {
          "version": 2,
          "name": "\(name)",
          "baseUrl": "\(baseURL)",
          "pages": [
            {
              "id": "home",
              "title": "Home",
              "type": "home",
              "url": "\(baseURL)",
              "ruleRefs": {
                "list": "home-list"
              }
            },
            {
              "id": "detail",
              "title": "Detail",
              "type": "detail",
              "ruleRefs": {
                "detail": "detail"
              }
            },
            {
              "id": "reader",
              "title": "Reader",
              "type": "reader",
              "ruleRefs": {
                "gallery": "reader-gallery"
              }
            }
          ],
          "ruleSets": {
            "listRules": [
              {
                "id": "home-list",
                "url": "\(baseURL)/list",
                "item": ".item",
                "title": ".title",
                "link": "a@href",
                "type": "comic"
              }
            ],
            "detailRules": [
              {
                "id": "detail",
                "chapterContainer": ".chapters",
                "chapterItem": "a",
                "chapterTitle": "text",
                "chapterLink": "href"
              }
            ],
            "galleryRules": [
              {
                "id": "reader-gallery",
                "imageItem": "img.page",
                "imageUrl": "src"
              }
            ]
          },
          "list": {
            "url": "\(baseURL)/list",
            "item": ".item",
            "title": ".title",
            "link": "a@href",
            "type": "comic"
          },
          "detail": {
            "chapterContainer": ".chapters",
            "chapterItem": "a",
            "chapterTitle": "text",
            "chapterLink": "href"
          },
          "gallery": {
            "imageItem": "img.page",
            "imageUrl": "src"
          }
        }
        """
    }
}

private final class InMemorySourceRepository: SourceRepository {
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
