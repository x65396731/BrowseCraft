import Foundation
import Testing
@testable import BrowseCraft

// 中文注释：ExtractRule 模型测试，覆盖旧单函数形态和新选择器/函数链形态。
struct ExtractRuleModelTests {
    @Test func legacySingleFunctionShapeDecodesWithoutAdvancedFields() throws {
        let json: String = """
        {
          "selector": "a.title",
          "function": "text",
          "regex": "(.+)",
          "replacement": "$1"
        }
        """

        let rule: ExtractRule = try JSONDecoder().decode(
            ExtractRule.self,
            from: Data(json.utf8)
        )

        // 中文注释：高级选择器和函数链字段必须保持可选，旧规则 JSON 不需要补 selectorKind/functions。
        #expect(rule.selector == "a.title")
        #expect(rule.selectorKind == nil)
        #expect(rule.function == .text)
        #expect(rule.functions == nil)
        // 中文注释：旧版 regex/replacement 仍然沿用单函数抽取路径，避免模型扩展破坏现有规则。
        #expect(rule.regex == "(.+)")
        #expect(rule.replacement == "$1")
    }

    @Test func selectorKindAndFunctionChainShapeDecode() throws {
        let json: String = """
        {
          "selector": "img.page",
          "selectorKind": "css",
          "function": "attr",
          "functions": [
            "attr",
            "removingPercentEncoding",
            "regexReplacement"
          ],
          "param": "data-src",
          "regex": "^(.+)$",
          "replacement": "$1"
        }
        """

        let rule: ExtractRule = try JSONDecoder().decode(
            ExtractRule.self,
            from: Data(json.utf8)
        )

        // 中文注释：selectorKind 用来记录选择器语法，未指定时默认仍走 CSS/SwiftSoup。
        #expect(rule.selector == "img.page")
        #expect(rule.selectorKind == .css)
        // 中文注释：function 继续作为兼容执行入口，functions 表达未来 Yealico 风格函数链。
        #expect(rule.function == .attr)
        #expect(rule.functions == [.attr, .removingPercentEncoding, .regexReplacement])
        // 中文注释：param 和 regex/replacement 需要能和函数链字段同时存在，供后续执行器复用。
        #expect(rule.param == "data-src")
        #expect(rule.regex == "^(.+)$")
        #expect(rule.replacement == "$1")
    }
}
