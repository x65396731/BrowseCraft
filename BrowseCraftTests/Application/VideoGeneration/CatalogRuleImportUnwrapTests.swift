import Foundation
import Testing
@testable import BrowseCraft

/// `importRuleJSON` 必须解到规则本体：单层、双层信封与已是本体的输入都得到同一结果。
struct CatalogRuleImportUnwrapTests {
    private static let body: CatalogRuleJSONValue = .object([
        "site": .object(["baseURL": .string("https://gimy.tv")]),
        "pages": .array([]),
        "ruleSets": .object([:])
    ])

    @Test func unwrapsSingleAndDoubleEnvelopes() {
        let single: CatalogRuleJSONValue = .object(["id": .string("x"), "ruleJSON": Self.body])
        let double: CatalogRuleJSONValue = .object(["id": .string("x"), "ruleJSON": single])

        #expect(single.importRuleJSON == Self.body)
        #expect(double.importRuleJSON == Self.body)
        #expect(Self.body.importRuleJSON == Self.body)
    }

    @Test func nonObjectRuleJSONIsNotUnwrapped() {
        let odd: CatalogRuleJSONValue = .object(["ruleJSON": .string("not-an-object")])
        #expect(odd.importRuleJSON == odd)
    }
}
