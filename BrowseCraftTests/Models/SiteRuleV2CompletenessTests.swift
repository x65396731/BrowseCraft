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
        #expect(rule.pages?.first?.tabGroup?.tabs.count == 2)
        #expect(rule.pages?.first?.tabGroup?.layout == .horizontalScroll)
        #expect(rule.pages?.first?.sections?.count == 2)
        #expect(rule.pages?.first?.sections?.last?.role == .recommendation)
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
        #expect(tabs.count == 2)
        #expect(tabs.map(\.id) == ["discover", "latest"])
        #expect(tabs.first?.title == "发现")
        #expect(tabs.first?.list.id == "home-list")
        #expect(tabs.first?.request?.scope == .page)
        #expect(tabs.first?.sections?.count == 2)
        #expect(tabs.first?.sections?.first?.id == "main-grid")
        #expect(tabs.first?.context?.pageId == "home")
        #expect(tabs.first?.context?.tabId == "discover")
        #expect(tabs[1].list.id == "latest-list")
        #expect(tabs[1].list.url == "https://example.test/latest/1")
        #expect(tabs[1].request?.headers?["X-Tab"] == "latest")
        #expect(tabs[1].context?.pageId == "home")
        #expect(tabs[1].context?.tabId == "latest")
        #expect(tabs[1].context?.sectionRole == .category)
        #expect(rule.primaryListRule.id == "home-list")
    }

    @Test func v2TabGroupSelectedTabBecomesDefaultListTab() throws {
        var rule: SiteRule = try JSONDecoder().decode(
            SiteRule.self,
            from: Data(RuleJSONFixtures.completeV2SiteRule.utf8)
        )

        rule.pages?[0].tabGroup?.selectedTabId = "latest"

        let tabs: [ListTabRule] = rule.availableListTabs

        // 中文注释：App 现阶段把第一个 ListTab 当默认入口；selectedTabId 要能把指定 tab 提到默认位置。
        #expect(tabs.map(\.id) == ["latest", "discover"])
        #expect(rule.primaryListRule.id == "latest-list")
    }

    @Test func v2RequestsResolveByRulePageAndSharedPriority() throws {
        var rule: SiteRule = try JSONDecoder().decode(
            SiteRule.self,
            from: Data(RuleJSONFixtures.strictComicV2SiteRule.utf8)
        )

        // 中文注释：请求配置按 Site → Page → Rule 合并，子层字段覆盖父层且保留未重写的共享字段。
        var resolvedRule = try Self.resolvedRule(for: rule)
        #expect(resolvedRule.primaryListEntry?.effectiveRequest?.scope == .rule)
        #expect(resolvedRule.primaryReaderEntry?.effectiveRequest?.scope == .rule)
        #expect(resolvedRule.primaryDetailEntry?.effectiveRequest?.scope == .site)
        #expect(resolvedRule.primaryListEntry?.effectiveRequest?.headers?["User-Agent"] == "BrowseCraft")

        rule.ruleSets?.listRules?[0].request = nil
        resolvedRule = try Self.resolvedRule(for: rule)
        #expect(resolvedRule.primaryListEntry?.effectiveRequest?.scope == .page)

        rule.pages?[0].request = nil
        resolvedRule = try Self.resolvedRule(for: rule)
        #expect(resolvedRule.primaryListEntry?.effectiveRequest?.scope == .site)
    }

    @Test func pageRequestCanDisableSharedWebViewForDetailOnly() throws {
        var rule: SiteRule = try JSONDecoder().decode(
            SiteRule.self,
            from: Data(RuleJSONFixtures.strictComicV2SiteRule.utf8)
        )
        rule.sharedRequest?.needsWebView = true
        rule.sharedRequest?.autoScroll = true
        rule.ruleSets?.detailRules?[0].request = nil
        rule.ruleSets?.galleryRules?[0].request = nil
        rule.pages?[1].request = RequestConfig(
            scope: .page,
            mergePolicy: .mergeHeaders,
            needsWebView: false,
            autoScroll: false
        )
        rule.pages?[2].request = RequestConfig(
            scope: .page,
            mergePolicy: .mergeHeadersAndCookies,
            needsWebView: true,
            autoScroll: true
        )

        let resolvedRule = try Self.resolvedRule(for: rule)

        #expect(resolvedRule.primaryDetailEntry?.effectiveRequest?.needsWebView == false)
        #expect(resolvedRule.primaryDetailEntry?.effectiveRequest?.autoScroll == false)
        #expect(resolvedRule.primaryDetailEntry?.effectiveRequest?.headers?["User-Agent"] == "BrowseCraft")
        #expect(resolvedRule.primaryReaderEntry?.effectiveRequest?.needsWebView == true)
        #expect(resolvedRule.primaryReaderEntry?.effectiveRequest?.autoScroll == true)
    }

    @Test func resolvedDetailAndGalleryEntriesKeepPageRulePairing() throws {
        var rule: SiteRule = try JSONDecoder().decode(
            SiteRule.self,
            from: Data(RuleJSONFixtures.strictComicV2SiteRule.utf8)
        )

        // 中文注释：ResolvedComicSiteRuleV2 应一次性固定 page 与 rule 的绑定。
        rule.ruleSets?.detailRules?[0].request = nil
        rule.ruleSets?.galleryRules?[0].request = nil
        let pageRequest: RequestConfig? = rule.pages?[0].request
        rule.pages?[1].request = pageRequest
        rule.pages?[2].request = pageRequest

        let resolvedRule = try Self.resolvedRule(for: rule)
        let detailEntry = try #require(resolvedRule.primaryDetailEntry)
        let readerEntry = try #require(resolvedRule.primaryReaderEntry)

        #expect(detailEntry.pageID == "detail")
        #expect(detailEntry.detailRuleID == "detail")
        #expect(resolvedRule.detailRule(for: detailEntry).id == "detail")
        #expect(detailEntry.effectiveRequest?.scope == .page)
        #expect(readerEntry.pageID == "reader")
        #expect(readerEntry.galleryRuleID == "reader-gallery")
        #expect(resolvedRule.galleryRule(for: readerEntry).id == "reader-gallery")
        #expect(readerEntry.effectiveRequest?.scope == .page)
    }

    @Test func resolvedDetailAndReaderContextsExposeDebugInputsWithoutRuleTuples() throws {
        var rule: SiteRule = try JSONDecoder().decode(
            SiteRule.self,
            from: Data(RuleJSONFixtures.strictComicV2SiteRule.utf8)
        )

        rule.ruleSets?.detailRules?[0].request = nil
        rule.ruleSets?.galleryRules?[0].request = RequestConfig(
            scope: .rule,
            mergePolicy: .override,
            method: .post,
            headers: ["X-Reader-Rule": "1"],
            body: nil,
            cookiePolicy: nil,
            cookiePriority: nil,
            cookieScope: nil,
            charset: nil,
            needsWebView: true,
            autoScroll: true,
            imageHeaders: nil,
            imageRequest: nil
        )

        let resolvedRule = try Self.resolvedRule(for: rule)
        let detailEntry = try #require(resolvedRule.primaryDetailEntry)
        let readerEntry = try #require(resolvedRule.primaryReaderEntry)

        #expect(detailEntry.pageID == "detail")
        #expect(detailEntry.detailRuleID == "detail")
        #expect(detailEntry.effectiveRequest?.scope == .site)
        #expect(resolvedRule.detailRule(for: detailEntry).id == "detail")

        #expect(readerEntry.pageID == "reader")
        #expect(readerEntry.galleryRuleID == "reader-gallery")
        #expect(readerEntry.effectiveRequest?.scope == .rule)
        #expect(readerEntry.effectiveRequest?.headers?["X-Reader-Rule"] == "1")
        #expect(resolvedRule.galleryRule(for: readerEntry).id == "reader-gallery")
    }

    @Test func v2DetailPageSelectsPrimaryDetailRule() throws {
        let rule: SiteRule = try JSONDecoder().decode(
            SiteRule.self,
            from: Data(RuleJSONFixtures.strictComicV2SiteRule.utf8)
        )

        let resolvedRule = try Self.resolvedRule(for: rule)
        let entry = try #require(resolvedRule.primaryDetailEntry)
        #expect(resolvedRule.detailRule(for: entry).id == "detail")
        #expect(resolvedRule.detailRule(for: entry).chapterRule?.title.selector == ".chapter-title")
    }

    @Test func v2ReaderPageSelectsPrimaryGalleryRule() throws {
        let rule: SiteRule = try JSONDecoder().decode(
            SiteRule.self,
            from: Data(RuleJSONFixtures.strictComicV2SiteRule.utf8)
        )

        let resolvedRule = try Self.resolvedRule(for: rule)
        let entry = try #require(resolvedRule.primaryReaderEntry)
        #expect(resolvedRule.galleryRule(for: entry).id == "reader-gallery")
        #expect(resolvedRule.galleryRule(for: entry).images?.item?.selector == "img.page")
    }

    private static func resolvedRule(for rule: SiteRule) throws -> ResolvedComicSiteRuleV2 {
        return try #require(
            ComicSiteRuleV2Validator().validate(rule: rule).resolvedRule
        )
    }
}
