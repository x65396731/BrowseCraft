import Foundation
import Testing
@testable import BrowseCraft

// 中文注释：完整 V2 规则模型测试，确认各子模型组合后仍能和旧规则字段共存。
struct SiteRuleV2CompletenessTests {
    @Test func completeV2RuleShapeDecodesWithLegacyFields() throws {
        let rule: SiteRule = try JSONDecoder().decode(
            SiteRule.self,
            from: Data(RuleJSONFixtures.completeV2SiteRule.utf8)
        )

        // 中文注释：完整性测试确认 V2 顶层结构和旧版必填字段可以共存，便于平滑迁移规则包。
        #expect(rule.version == 2)
        #expect(rule.site?.domain == "example.test")
        #expect(rule.list.type == .comic)
        #expect(rule.gallery?.imageItem == "img.page")
        #expect(rule.video?.videoUrl == "https://media.example/video.mp4")
        // 中文注释：URL 模板、页面入口和规则引用需要能在同一份规则 JSON 中同时表达。
        #expect(rule.urlPatterns?.detailTemplate?.placeholders?.first?.kind == .idCode)
        #expect(rule.urlPatterns?.galleryTemplate?.placeholders?.first?.kind == .cidCode)
        #expect(rule.urlPatterns?.searchTemplate?.placeholders?.last?.kind == .urlQuery)
        #expect(rule.pages?.count == 2)
        #expect(rule.pages?.first?.ruleRefs?.list == "home-list")
        #expect(rule.pages?.last?.displayMode == .verticalReader)
        // 中文注释：共享请求、页面请求、规则请求、图片请求都要能 decode 出优先级字段。
        #expect(rule.sharedRequest?.scope == .site)
        #expect(rule.sharedRequest?.imageRequest?.cookieScope == .image)
        #expect(rule.pages?.first?.request?.scope == .page)
        #expect(rule.ruleSets?.listRules?.first?.request?.mergePolicy == .mergeHeadersAndCookies)
        #expect(rule.ruleSets?.galleryRules?.first?.request?.imageRequest?.headers?["Referer"] == "https://example.test/reader")
        // 中文注释：抽取、字段、嵌套规则和搜索规则组合到完整规则后仍要保持可读可解码。
        let listFields: ListFields? = rule.ruleSets?.listRules?.first?.fields
        #expect(listFields?.largeImage?.param == "data-src")
        #expect(listFields?.detailURL.fallback?.first?.selector == "a.cover")
        #expect(rule.ruleSets?.detailRules?.first?.fields?.totalImages?.functions == [.text, .regexReplacement])
        #expect(rule.ruleSets?.detailRules?.first?.chapterRule?.cidCode?.param == "data-cid")
        #expect(rule.ruleSets?.detailRules?.first?.tagRule?.name?.selector == "this")
        #expect(rule.ruleSets?.detailRules?.first?.commentRule?.avatar?.param == "src")
        #expect(rule.ruleSets?.detailRules?.first?.videoRule?.thumbnail?.param == "poster")
        #expect(rule.ruleSets?.galleryRules?.first?.image?.functions == [.attr, .removingPercentEncoding])
        #expect(rule.ruleSets?.searchRules?.first?.fields.detailURL.function == .url)
    }
}
