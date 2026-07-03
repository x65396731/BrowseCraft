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
        #expect(rule.pages?.count == 3)
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

    @Test func ruleSetsFindRulesByStableID() throws {
        let rule: SiteRule = try JSONDecoder().decode(
            SiteRule.self,
            from: Data(RuleJSONFixtures.completeV2SiteRule.utf8)
        )

        // 中文注释：PageRule.ruleRefs 后续会以稳定 id 接到 RuleSets，这里先锁定模型层查找行为。
        let ruleSets: RuleSets = try #require(rule.ruleSets)
        #expect(ruleSets.listRule(id: "home-list")?.id == "home-list")
        #expect(ruleSets.detailRule(id: "detail")?.id == "detail")
        #expect(ruleSets.galleryRule(id: "reader-gallery")?.id == "reader-gallery")
        #expect(ruleSets.searchRule(id: "search")?.id == "search")
    }

    @Test func ruleSetsIgnoreBlankOrMissingIDs() throws {
        let rule: SiteRule = try JSONDecoder().decode(
            SiteRule.self,
            from: Data(RuleJSONFixtures.completeV2SiteRule.utf8)
        )

        // 中文注释：空白引用不能误命中第一条规则；带空格的有效 id 允许被规范化后命中。
        let ruleSets: RuleSets = try #require(rule.ruleSets)
        #expect(ruleSets.listRule(id: " home-list ")?.id == "home-list")
        #expect(ruleSets.listRule(id: nil) == nil)
        #expect(ruleSets.detailRule(id: "") == nil)
        #expect(ruleSets.galleryRule(id: "   ") == nil)
        #expect(ruleSets.searchRule(id: "missing") == nil)
    }

    @Test func v2ListPagesBecomeAvailableListTabs() throws {
        let rule: SiteRule = try JSONDecoder().decode(
            SiteRule.self,
            from: Data(RuleJSONFixtures.completeV2SiteRule.utf8)
        )

        // 中文注释：列表入口要从 PageRule.ruleRefs.list 接到 RuleSets.listRules，UI 和刷新用例才能共用 V2 页面定义。
        let tabs: [ListTabRule] = rule.availableListTabs
        #expect(tabs.count == 1)
        #expect(tabs.first?.id == "home")
        #expect(tabs.first?.title == "Home")
        #expect(tabs.first?.list.id == "home-list")
        #expect(tabs.first?.request?.scope == .page)
        #expect(rule.primaryListRule.id == "home-list")
    }

    @Test func v2ListPagesMergeAdditionalLegacyListTabs() throws {
        var rule: SiteRule = try JSONDecoder().decode(
            SiteRule.self,
            from: Data(RuleJSONFixtures.completeV2SiteRule.utf8)
        )
        let duplicateHomeListTab: ListTabRule = ListTabRule(
            id: "legacy-home",
            title: "Duplicate Home",
            list: rule.primaryListRule
        )
        let updatedListTab: ListTabRule = ListTabRule(
            id: "updated",
            title: "Updated",
            list: ListRule(
                id: "updated-list",
                url: "https://example.test/updated/{page}",
                text: nil,
                item: ".comic-card",
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
        )
        rule.listTabs = [
            duplicateHomeListTab,
            updatedListTab
        ]

        let tabs: [ListTabRule] = rule.availableListTabs

        // 中文注释：V2 PageRule 仍是主入口，但旧 listTabs 中不同的分类入口不能被整个丢弃。
        #expect(tabs.map(\.id) == ["home", "updated"])
        #expect(tabs.map { tab in tab.list.id } == ["home-list", "updated-list"])
    }

    @Test func v2RequestsResolveByRulePageAndSharedPriority() throws {
        var rule: SiteRule = try JSONDecoder().decode(
            SiteRule.self,
            from: Data(RuleJSONFixtures.completeV2SiteRule.utf8)
        )

        // 中文注释：请求配置按 Rule > Page > Site sharedRequest 选择，P1-4.1 先锁定选择结果，不在模型层做深度合并。
        #expect(rule.primaryListRequest?.scope == .rule)
        #expect(rule.primaryGalleryRequest?.scope == .image)
        #expect(rule.primaryDetailRequest?.scope == .site)

        rule.ruleSets?.listRules?[0].request = nil
        #expect(rule.primaryListRequest?.scope == .page)

        rule.pages?[0].request = nil
        #expect(rule.primaryListRequest?.scope == .site)
    }

    @Test func v2DetailPageSelectsPrimaryDetailRule() throws {
        let rule: SiteRule = try JSONDecoder().decode(
            SiteRule.self,
            from: Data(RuleJSONFixtures.completeV2SiteRule.utf8)
        )

        // 中文注释：详情解析入口要从 PageRule.ruleRefs.detail 接到 RuleSets.detailRules，旧 detail 字段只作为兼容兜底。
        #expect(rule.primaryDetailRule?.id == "detail")
        #expect(rule.primaryDetailRule?.chapterRule?.title.selector == ".chapter-title")
    }

    @Test func v2ReaderPageSelectsPrimaryGalleryRule() throws {
        let rule: SiteRule = try JSONDecoder().decode(
            SiteRule.self,
            from: Data(RuleJSONFixtures.completeV2SiteRule.utf8)
        )

        // 中文注释：阅读页图片解析入口要从 PageRule.ruleRefs.gallery 接到 RuleSets.galleryRules，旧 gallery 字段只作为兼容兜底。
        #expect(rule.primaryGalleryRule?.id == "reader-gallery")
        #expect(rule.primaryGalleryRule?.imageItem == "img.page")
    }
}
