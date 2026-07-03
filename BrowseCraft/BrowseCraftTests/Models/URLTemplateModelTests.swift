import Foundation
import Testing
@testable import BrowseCraft

// 中文注释：URL 模板模型测试，覆盖旧字符串 URL 和结构化占位符模板。
struct URLTemplateModelTests {
    @Test func legacyURLPatternStringsDecode() throws {
        let json: String = """
        {
          "series": "https://example.test/comics/{idCode:}",
          "list": "https://example.test/list/{page}",
          "detail": "https://example.test/detail/{idCode:}",
          "gallery": "https://example.test/chapter/{cidCode:}",
          "search": "https://example.test/search?q={keyword:}"
        }
        """

        let patterns: URLPatterns = try JSONDecoder().decode(
            URLPatterns.self,
            from: Data(json.utf8)
        )

        // 中文注释：旧字符串格式仍然可解码，规则包不需要一次性迁移到结构化模板。
        #expect(patterns.series == "https://example.test/comics/{idCode:}")
        #expect(patterns.list == "https://example.test/list/{page}")
        #expect(patterns.detail == "https://example.test/detail/{idCode:}")
        #expect(patterns.gallery == "https://example.test/chapter/{cidCode:}")
        #expect(patterns.search == "https://example.test/search?q={keyword:}")
        // 中文注释：旧字符串格式 decode 时，新模板字段应保持为空，由现有执行流继续处理旧 URL。
        #expect(patterns.seriesTemplate == nil)
        #expect(patterns.listTemplate == nil)
        #expect(patterns.detailTemplate == nil)
        #expect(patterns.galleryTemplate == nil)
        #expect(patterns.searchTemplate == nil)
    }

    @Test func structuredURLTemplatesDecodePlaceholders() throws {
        let json: String = """
        {
          "listTemplate": {
            "template": "https://example.test/list/{page:1:20}",
            "placeholders": [
              {
                "kind": "page",
                "start": 1,
                "step": 20
              }
            ]
          },
          "searchTemplate": {
            "template": "https://example.test/search?q={keyword:}&from={urlQuery:from}",
            "placeholders": [
              {
                "kind": "keyword",
                "encoding": "urlQueryAllowed"
              },
              {
                "kind": "urlQuery",
                "name": "from",
                "defaultValue": "home"
              }
            ]
          }
        }
        """

        let patterns: URLPatterns = try JSONDecoder().decode(
            URLPatterns.self,
            from: Data(json.utf8)
        )

        // 中文注释：结构化模板记录原始模板字符串，后续执行器才能按页面类型选择 URL。
        #expect(patterns.listTemplate?.template == "https://example.test/list/{page:1:20}")
        #expect(patterns.searchTemplate?.template == "https://example.test/search?q={keyword:}&from={urlQuery:from}")

        let pagePlaceholder: URLPlaceholderRule? = patterns.listTemplate?.placeholders?.first
        // 中文注释：{page:start:step} 必须能表达起始页和步长，支持非 1 递增分页。
        #expect(pagePlaceholder?.kind == .page)
        #expect(pagePlaceholder?.start == 1)
        #expect(pagePlaceholder?.step == 20)

        let searchPlaceholders: [URLPlaceholderRule] = patterns.searchTemplate?.placeholders ?? []
        // 中文注释：{keyword:} 和 {urlQuery:key} 是搜索/二级跳转常用占位符，需要能共存。
        #expect(searchPlaceholders.count == 2)
        #expect(searchPlaceholders[0].kind == .keyword)
        #expect(searchPlaceholders[0].encoding == .urlQueryAllowed)
        #expect(searchPlaceholders[1].kind == .urlQuery)
        #expect(searchPlaceholders[1].name == "from")
        #expect(searchPlaceholders[1].defaultValue == "home")
    }
}
