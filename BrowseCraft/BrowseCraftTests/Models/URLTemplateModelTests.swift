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
        try Self.assertLegacySearchURLRendering()
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
        try Self.assertStructuredSearchURLRendering()
        try Self.assertListPagePlaceholderRendering()
        try Self.assertDefaultQueryPlaceholderRendering()
        try Self.assertRawKeywordSearchURLRendering()
    }

    private static func assertLegacySearchURLRendering() throws {
        let source: Source = Self.source(baseURL: "https://example.test/root")
        let searchRule: SearchRule = Self.searchRule(url: "/search?q={keyword:}&page={page}")
        let url: URL = try URLResolvingService().searchURL(
            for: source,
            searchRule: searchRule,
            keyword: "钢炼 & test",
            page: 2
        )

        #expect(url.absoluteString == "https://example.test/search?q=%E9%92%A2%E7%82%BC%20%26%20test&page=2")
    }

    private static func assertStructuredSearchURLRendering() throws {
        let template: URLTemplateRule = URLTemplateRule(
            template: "/search?q={keyword:}&from={urlQuery:from}&offset={page:1:20}",
            placeholders: [
                URLPlaceholderRule(
                    kind: .keyword,
                    name: nil,
                    start: nil,
                    step: nil,
                    index: nil,
                    defaultValue: nil,
                    encoding: .urlQueryAllowed
                ),
                URLPlaceholderRule(
                    kind: .urlQuery,
                    name: "from",
                    start: nil,
                    step: nil,
                    index: nil,
                    defaultValue: "home",
                    encoding: nil
                ),
                URLPlaceholderRule(
                    kind: .page,
                    name: nil,
                    start: 1,
                    step: 20,
                    index: nil,
                    defaultValue: nil,
                    encoding: nil
                )
            ]
        )
        let source: Source = Self.source(
            baseURL: "https://example.test/root?from=library",
            urlPatterns: URLPatterns(
                series: nil,
                seriesTemplate: nil,
                list: nil,
                listTemplate: nil,
                detail: nil,
                detailTemplate: nil,
                gallery: nil,
                galleryTemplate: nil,
                search: nil,
                searchTemplate: template
            )
        )
        let searchRule: SearchRule = Self.searchRule(url: "/legacy?q={keyword:}")

        let url: URL = try URLResolvingService().searchURL(
            for: source,
            searchRule: searchRule,
            keyword: "猫",
            page: 3
        )

        #expect(url.absoluteString == "https://example.test/search?q=%E7%8C%AB&from=library&offset=41")
    }

    private static func assertListPagePlaceholderRendering() throws {
        var source: Source = Self.source(baseURL: "https://example.test")
        source.rule.list.url = "/list/{page:0:30}"

        let url: URL = try URLResolvingService().listURL(for: source, page: 3)

        #expect(url.absoluteString == "https://example.test/list/60")
    }

    private static func assertDefaultQueryPlaceholderRendering() throws {
        let source: Source = Self.source(baseURL: "https://example.test")
        let template: URLTemplateRule = URLTemplateRule(
            template: "/search?from={urlQuery:from}",
            placeholders: [
                URLPlaceholderRule(
                    kind: .urlQuery,
                    name: "from",
                    start: nil,
                    step: nil,
                    index: nil,
                    defaultValue: "home",
                    encoding: nil
                )
            ]
        )

        let url: URL = try URLResolvingService().templateURL(for: source, template: template)

        #expect(url.absoluteString == "https://example.test/search?from=home")
    }

    private static func assertRawKeywordSearchURLRendering() throws {
        let source: Source = Self.source(baseURL: "https://example.test")
        let searchRule: SearchRule = Self.searchRule(url: "/search?q={keyword:}", keywordEncoding: .raw)

        let url: URL = try URLResolvingService().searchURL(
            for: source,
            searchRule: searchRule,
            keyword: "raw+keyword",
            page: 1
        )

        #expect(url.absoluteString == "https://example.test/search?q=raw+keyword")
    }

    private static func source(baseURL: String, urlPatterns: URLPatterns? = nil) -> Source {
        let listRule: ListRule = ListRule(
            id: "list",
            url: "/list/{page}",
            text: nil,
            item: ".item",
            itemRule: nil,
            fields: nil,
            title: ".title",
            link: "a@href",
            cover: nil,
            type: .comic,
            latestText: nil,
            pagination: nil,
            ready: nil,
            request: nil,
            js: nil
        )
        let rule: SiteRule = SiteRule(
            version: 2,
            site: nil,
            urlPatterns: urlPatterns,
            pages: nil,
            ruleSets: nil,
            sharedRequest: nil,
            flags: nil,
            name: "Example",
            baseUrl: baseURL,
            list: listRule,
            listTabs: nil,
            detail: nil,
            gallery: nil,
            video: nil
        )

        return Source(
            id: "source.example",
            name: "Example",
            baseURL: baseURL,
            type: .html,
            rule: rule,
            enabled: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private static func searchRule(
        url: String,
        keywordEncoding: KeywordEncoding = .urlQueryAllowed
    ) -> SearchRule {
        return SearchRule(
            id: "search",
            keywordEncoding: keywordEncoding,
            url: url,
            method: .get,
            request: nil,
            listRuleRef: nil,
            item: ExtractRule(
                selector: ".result",
                selectorKind: nil,
                function: .raw,
                functions: nil,
                param: nil,
                regex: nil,
                replacement: nil,
                fallback: nil
            ),
            fields: ListFields(
                idCode: nil,
                title: ExtractRule(
                    selector: ".title",
                    selectorKind: nil,
                    function: .text,
                    functions: nil,
                    param: nil,
                    regex: nil,
                    replacement: nil,
                    fallback: nil
                ),
                cover: nil,
                largeImage: nil,
                video: nil,
                detailURL: ExtractRule(
                    selector: "a",
                    selectorKind: nil,
                    function: .url,
                    functions: nil,
                    param: nil,
                    regex: nil,
                    replacement: nil,
                    fallback: nil
                ),
                latestText: nil,
                description: nil,
                coverWidth: nil,
                coverHeight: nil,
                category: nil,
                author: nil,
                uploader: nil,
                publishedAt: nil,
                datetime: nil,
                rating: nil,
                totalImages: nil,
                language: nil
            ),
            pagination: nil
        )
    }
}
