import Foundation
import Testing
@testable import BrowseCraft

struct SwiftSoupDetailParserTests {
    @Test func v2ChapterRulesApplyFunctionChains() throws {
        let source: Source = try Self.v2FunctionChainSource()
        let parser: SwiftSoupComicRuleSourceParser = SwiftSoupComicRuleSourceParser(
            urlResolver: URLResolvingService()
        )

        let chapters: [ChapterLink] = try parser.parseDetailChapters(
            html: """
            <main>
              <div class="chapter">
                <span class="title">Chapter 01 extra</span>
                <a class="link" data-url="/reader%2Fone">Read</a>
              </div>
            </main>
            """,
            source: source,
            pageURL: "https://example.test/comics/100"
        )

        // 中文注释：标题先 text 再 regexReplacement，证明 functions 会按数组顺序转换字符串。
        #expect(chapters.first?.title == "第01话")
        // 中文注释：链接先读取 data-url 再 removingPercentEncoding，最终仍通过 URLResolvingService 转成绝对 URL。
        #expect(chapters.first?.url == "https://example.test/reader/one")
    }

    @Test func v2ChapterRulesUseFallbackWhenPrimaryResultIsBlankOrMissing() throws {
        let source: Source = try Self.v2FallbackSource()
        let parser: SwiftSoupComicRuleSourceParser = SwiftSoupComicRuleSourceParser(
            urlResolver: URLResolvingService()
        )

        let chapters: [ChapterLink] = try parser.parseDetailChapters(
            html: """
            <main>
              <div class="chapter">
                <span class="primary-title">   </span>
                <span class="fallback-title">第02话</span>
                <a class="fallback-link" href="/reader/two">Read</a>
              </div>
            </main>
            """,
            source: source,
            pageURL: "https://example.test/comics/100"
        )

        // 中文注释：主标题 selector 有节点但只返回空白时，应继续使用 fallback 标题规则。
        #expect(chapters.first?.title == "第02话")
        // 中文注释：主链接 selector 缺失时，应继续使用 fallback 链接规则并完成绝对 URL 解析。
        #expect(chapters.first?.url == "https://example.test/reader/two")
    }

    @Test func v2ChapterRulesApplyReplaceFunctionInChain() throws {
        let source: Source = try Self.v2ReplaceFunctionSource()
        let parser: SwiftSoupComicRuleSourceParser = SwiftSoupComicRuleSourceParser(
            urlResolver: URLResolvingService()
        )

        let chapters: [ChapterLink] = try parser.parseDetailChapters(
            html: """
            <main>
              <div class="chapter">
                <span class="title">Episode 03</span>
                <a class="link" href="/reader/three">Read</a>
              </div>
            </main>
            """,
            source: source,
            pageURL: "https://example.test/comics/100"
        )

        // 中文注释：replace 使用 param 作为目标文本、replacement 作为替换文本，确认函数链可做轻量字符串清洗。
        #expect(chapters.first?.title == "第03")
        #expect(chapters.first?.url == "https://example.test/reader/three")
    }

    @Test func v2ChapterRulesApplyDecompressFromBase64FunctionInChain() throws {
        let source: Source = try Self.v2DecompressFromBase64Source()
        let parser: SwiftSoupComicRuleSourceParser = SwiftSoupComicRuleSourceParser(
            urlResolver: URLResolvingService()
        )

        let chapters: [ChapterLink] = try parser.parseDetailChapters(
            html: """
            <main>
              <div class="chapter">
                <span class="encoded-title">e75mjYEJAA==</span>
                <a class="link" href="/reader/four">Read</a>
              </div>
            </main>
            """,
            source: source,
            pageURL: "https://example.test/comics/100"
        )

        // 中文注释：fixture 是字符串“第04”的 zlib 压缩结果再 Base64 编码，用来固定 decompressFromBase64 的算法边界。
        #expect(chapters.first?.title == "第04")
        #expect(chapters.first?.url == "https://example.test/reader/four")
    }

    @Test func v2ChapterRulesUseCurrentSelectorKindForItemText() throws {
        let source: Source = try Self.v2CurrentSelectorKindSource()
        let parser: SwiftSoupComicRuleSourceParser = SwiftSoupComicRuleSourceParser(
            urlResolver: URLResolvingService()
        )

        let chapters: [ChapterLink] = try parser.parseDetailChapters(
            html: """
            <main>
              <a class="chapter" href="/reader/five">第05话</a>
            </main>
            """,
            source: source,
            pageURL: "https://example.test/comics/100"
        )

        // 中文注释：selectorKind=current 明确表示使用当前章节 item 元素，不再依赖 legacy 的 selector="this" 字符串。
        #expect(chapters.first?.title == "第05话")
        #expect(chapters.first?.url == "https://example.test/reader/five")
    }

    @Test func v2PageRuleRefsSelectRuleSetsDetailRule() throws {
        let source: Source = try Self.v2DetailRuleSourceWithLegacyDetailDisabled()
        let parser: SwiftSoupComicRuleSourceParser = SwiftSoupComicRuleSourceParser(
            urlResolver: URLResolvingService()
        )

        let chapters: [ChapterLink] = try parser.parseDetailChapters(
            html: """
            <main>
              <div class="chapter" data-id="101" data-cid="201">
                <span class="chapter-title">V2 第01话</span>
                <a class="chapter-link" href="/chapters/v2-1">Read</a>
              </div>
              <div class="chapter" data-id="102" data-cid="202">
                <span class="chapter-title">V2 第02话</span>
                <a class="chapter-link" href="/chapters/v2-2">Read</a>
              </div>
            </main>
            """,
            source: source,
            pageURL: "https://example.test/comics/v2"
        )

        // 中文注释：旧版 detail 已置空；能解析出章节说明默认入口确实走了 V2 Page -> RuleSets.detailRules。
        #expect(chapters.count == 2)
        #expect(chapters[0].title == "V2 第01话")
        #expect(chapters[0].url == "https://example.test/chapters/v2-1")
        #expect(chapters[1].title == "V2 第02话")
        #expect(chapters[1].url == "https://example.test/chapters/v2-2")
    }

    @Test func v2DetailChaptersUseListContextScope() throws {
        let source: Source = try Self.v2DetailRuleSourceWithLegacyDetailDisabled()
        let parser: SwiftSoupComicRuleSourceParser = SwiftSoupComicRuleSourceParser(
            urlResolver: URLResolvingService()
        )

        let chapters: [ChapterLink] = try parser.parseDetailChapters(
            html: """
            <main>
              <section data-section-id="main-grid" data-section-role="main">
                <div class="chapter" data-id="101" data-cid="201">
                  <span class="chapter-title">主内容 第01话</span>
                  <a class="chapter-link" href="/chapters/main-1">Read</a>
                </div>
              </section>
              <section data-section-id="recommendations" data-section-role="recommendation">
                <div class="chapter" data-id="999" data-cid="999">
                  <span class="chapter-title">推荐区 第99话</span>
                  <a class="chapter-link" href="/chapters/recommend-99">Read</a>
                </div>
              </section>
            </main>
            """,
            source: source,
            pageURL: "https://example.test/comics/v2",
            context: ListContext(
                pageId: "home",
                tabId: "home",
                sectionId: "main-grid",
                listRuleId: "home-list",
                sectionRole: .main
            )
        )

        // 中文注释：P1-5.3 详情解析应优先使用列表项来源 section，只解析主内容区章节。
        #expect(chapters.map(\.title) == ["主内容 第01话"])
        #expect(chapters.map(\.url) == ["https://example.test/chapters/main-1"])
    }

    private static func v2FunctionChainSource() throws -> Source {
        let ruleJSON: String = """
        {
          "name": "Function Chain Test",
          "baseUrl": "https://example.test",
          "list": {
            "url": "https://example.test/list",
            "item": ".card",
            "title": ".title",
            "link": "a@href",
            "type": "comic"
          },
          "detail": {
            "chapterRule": {
              "item": {
                "selector": ".chapter",
                "function": "raw"
              },
              "title": {
                "selector": ".title",
                "function": "text",
                "functions": [
                  "text",
                  "regexReplacement"
                ],
                "regex": "Chapter (\\\\d+).*",
                "replacement": "第$1话"
              },
              "url": {
                "selector": "a.link",
                "function": "url",
                "functions": [
                  "url",
                  "removingPercentEncoding"
                ],
                "param": "data-url"
              }
            }
          },
          "gallery": {
            "imageItem": "img",
            "imageUrl": "this@src"
          }
        }
        """

        let rule: SiteRule = try JSONDecoder().decode(
            SiteRule.self,
            from: Data(ruleJSON.utf8)
        )

        // 中文注释：测试专用 Source 只承载最小 V2 detail rule，避免依赖远端规则包或真实网页。
        return Source(
            id: "function-chain-test",
            name: "Function Chain Test",
            baseURL: "https://example.test",
            type: .html,
            rule: rule,
            enabled: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private static func v2FallbackSource() throws -> Source {
        let ruleJSON: String = """
        {
          "name": "Fallback Test",
          "baseUrl": "https://example.test",
          "list": {
            "url": "https://example.test/list",
            "item": ".card",
            "title": ".title",
            "link": "a@href",
            "type": "comic"
          },
          "detail": {
            "chapterRule": {
              "item": {
                "selector": ".chapter",
                "function": "raw"
              },
              "title": {
                "selector": ".primary-title",
                "function": "text",
                "fallback": [
                  {
                    "selector": ".fallback-title",
                    "function": "text"
                  }
                ]
              },
              "url": {
                "selector": "a.missing",
                "function": "url",
                "fallback": [
                  {
                    "selector": "a.fallback-link",
                    "function": "url"
                  }
                ]
              }
            }
          },
          "gallery": {
            "imageItem": "img",
            "imageUrl": "this@src"
          }
        }
        """

        let rule: SiteRule = try JSONDecoder().decode(
            SiteRule.self,
            from: Data(ruleJSON.utf8)
        )

        // 中文注释：测试专用 Source 聚焦 ExtractRule.fallback，不依赖列表页或真实网络数据。
        return Source(
            id: "fallback-test",
            name: "Fallback Test",
            baseURL: "https://example.test",
            type: .html,
            rule: rule,
            enabled: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private static func v2ReplaceFunctionSource() throws -> Source {
        let ruleJSON: String = """
        {
          "name": "Replace Function Test",
          "baseUrl": "https://example.test",
          "list": {
            "url": "https://example.test/list",
            "item": ".card",
            "title": ".title",
            "link": "a@href",
            "type": "comic"
          },
          "detail": {
            "chapterRule": {
              "item": {
                "selector": ".chapter",
                "function": "raw"
              },
              "title": {
                "selector": ".title",
                "function": "text",
                "functions": [
                  "text",
                  "replace"
                ],
                "param": "Episode ",
                "replacement": "第"
              },
              "url": {
                "selector": "a.link",
                "function": "url"
              }
            }
          },
          "gallery": {
            "imageItem": "img",
            "imageUrl": "this@src"
          }
        }
        """

        let rule: SiteRule = try JSONDecoder().decode(
            SiteRule.self,
            from: Data(ruleJSON.utf8)
        )

        // 中文注释：测试专用 Source 聚焦 replace 函数，不依赖远端规则包或真实网页。
        return Source(
            id: "replace-function-test",
            name: "Replace Function Test",
            baseURL: "https://example.test",
            type: .html,
            rule: rule,
            enabled: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private static func v2DecompressFromBase64Source() throws -> Source {
        let ruleJSON: String = """
        {
          "name": "Decompress Function Test",
          "baseUrl": "https://example.test",
          "list": {
            "url": "https://example.test/list",
            "item": ".card",
            "title": ".title",
            "link": "a@href",
            "type": "comic"
          },
          "detail": {
            "chapterRule": {
              "item": {
                "selector": ".chapter",
                "function": "raw"
              },
              "title": {
                "selector": ".encoded-title",
                "function": "text",
                "functions": [
                  "text",
                  "decompressFromBase64"
                ]
              },
              "url": {
                "selector": "a.link",
                "function": "url"
              }
            }
          },
          "gallery": {
            "imageItem": "img",
            "imageUrl": "this@src"
          }
        }
        """

        let rule: SiteRule = try JSONDecoder().decode(
            SiteRule.self,
            from: Data(ruleJSON.utf8)
        )

        // 中文注释：测试专用 Source 聚焦 zlib+Base64 解压，不依赖远端规则包或真实网页。
        return Source(
            id: "decompress-function-test",
            name: "Decompress Function Test",
            baseURL: "https://example.test",
            type: .html,
            rule: rule,
            enabled: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private static func v2CurrentSelectorKindSource() throws -> Source {
        let ruleJSON: String = """
        {
          "name": "Current Selector Kind Test",
          "baseUrl": "https://example.test",
          "list": {
            "url": "https://example.test/list",
            "item": ".card",
            "title": ".title",
            "link": "a@href",
            "type": "comic"
          },
          "detail": {
            "chapterRule": {
              "item": {
                "selector": "a.chapter",
                "function": "raw"
              },
              "title": {
                "selectorKind": "current",
                "function": "text"
              },
              "url": {
                "selectorKind": "current",
                "function": "url"
              }
            }
          },
          "gallery": {
            "imageItem": "img",
            "imageUrl": "this@src"
          }
        }
        """

        let rule: SiteRule = try JSONDecoder().decode(
            SiteRule.self,
            from: Data(ruleJSON.utf8)
        )

        // 中文注释：测试专用 Source 聚焦 selectorKind=current，不依赖 legacy selector="this" 字符串。
        return Source(
            id: "current-selector-kind-test",
            name: "Current Selector Kind Test",
            baseURL: "https://example.test",
            type: .html,
            rule: rule,
            enabled: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private static func v2DetailRuleSourceWithLegacyDetailDisabled() throws -> Source {
        var rule: SiteRule = try JSONDecoder().decode(
            SiteRule.self,
            from: Data(RuleJSONFixtures.completeV2SiteRule.utf8)
        )

        // 中文注释：禁用旧版 detail 字段，让测试只能通过 PageRule.ruleRefs.detail 指向的 V2 detailRules 成功。
        rule.detail = nil

        return Source(
            id: "v2-detail-source",
            name: "V2 Detail Source",
            baseURL: "https://example.test",
            type: .html,
            rule: rule,
            enabled: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
