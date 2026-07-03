import Foundation

// 中文注释：SiteRule.swift 属于领域模型层，用于说明本文件承载的核心职责。

/// 中文注释：站点规则描述 BrowseCraft 如何从某个源站抽取内容。
/// 中文注释：它属于领域数据，不关心底层使用 SwiftSoup、JSON 解析器还是其他解析器。
struct SiteRule: Codable, Hashable {
    /// 中文注释：V2 规则版本号；旧版扁平规则未提供时按旧解析链路处理。
    var version: Int?
    /// 中文注释：站点级配置，承载域名、语言、展示模式等非抽取字段。
    var site: SiteConfig?
    /// 中文注释：站点常见 URL 形态，用于识别列表、详情、阅读页和搜索页。
    var urlPatterns: URLPatterns?
    /// 中文注释：V2 页面入口定义；用于描述首页、分类、搜索、详情和阅读页之间的关系。
    var pages: [PageRule]?
    /// 中文注释：V2 规则集合；新规则优先放这里，旧字段保留用于兼容。
    var ruleSets: RuleSets?
    /// 中文注释：站点级请求配置，页面和规则可覆盖。
    var sharedRequest: RequestConfig?
    var flags: [SiteFlag]?
    var name: String
    var baseUrl: String
    var list: ListRule
    var listTabs: [ListTabRule]?
    var detail: DetailRule?
    var gallery: GalleryRule?
    var video: VideoRule?

    var primaryListRule: ListRule {
        return self.availableListTabs.first?.list ?? self.list
    }

    var primaryDetailRule: DetailRule? {
        return RuleResolver().resolve(self).primaryDetailRule
    }

    var primaryGalleryRule: GalleryRule? {
        return RuleResolver().resolve(self).primaryGalleryRule
    }

    var primaryListRequest: RequestConfig? {
        return self.request(for: self.availableListTabs.first)
    }

    var primaryDetailRequest: RequestConfig? {
        return RuleResolver().resolve(self).primaryDetailRequest
    }

    var primaryGalleryRequest: RequestConfig? {
        return RuleResolver().resolve(self).primaryGalleryRequest
    }

    var availableListTabs: [ListTabRule] {
        let pageListTabs: [ListTabRule] = self.pageListTabs
        if pageListTabs.isEmpty == false {
            return self.mergedListTabs(
                pageListTabs: pageListTabs,
                legacyListTabs: self.listTabs ?? []
            )
        }

        if let listTabs: [ListTabRule] = self.listTabs, listTabs.isEmpty == false {
            return listTabs
        }

        return [
            ListTabRule(
                id: "default",
                title: "发现",
                list: self.list
            )
        ]
    }

    /// 中文注释：V2 Pages 是主入口，但旧 listTabs 里可能还有分类入口；按 tab id 和 list rule id 去重后保留它们。
    private func mergedListTabs(pageListTabs: [ListTabRule], legacyListTabs: [ListTabRule]) -> [ListTabRule] {
        guard legacyListTabs.isEmpty == false else {
            return pageListTabs
        }

        let pageTabIDs: Set<String> = Set(pageListTabs.map { tab in tab.id })
        let pageListRuleIDs: Set<String> = Set(
            pageListTabs.compactMap { tab in
                return tab.list.id
            }
        )
        let additionalLegacyTabs: [ListTabRule] = legacyListTabs.filter { tab in
            if pageTabIDs.contains(tab.id) {
                return false
            }

            if let listRuleID: String = tab.list.id,
               pageListRuleIDs.contains(listRuleID) {
                return false
            }

            return true
        }

        return pageListTabs + additionalLegacyTabs
    }

    private var pageListTabs: [ListTabRule] {
        guard let pages: [PageRule] = self.pages,
              let ruleSets: RuleSets = self.ruleSets else {
            return []
        }

        // 中文注释：V2 的 Pages 是界面入口，ruleRefs.list 指向 RuleSets.listRules 中真正执行的列表规则。
        var listTabs: [ListTabRule] = []

        for page: PageRule in pages where page.isListEntryPage {
            listTabs.append(
                contentsOf: self.pageListTabs(
                    page: page,
                    pages: pages,
                    ruleSets: ruleSets
                )
            )
        }

        return listTabs
    }

    private func pageListTabs(page: PageRule, pages: [PageRule], ruleSets: RuleSets) -> [ListTabRule] {
        if let tabGroup: TabGroupRule = page.tabGroup,
           tabGroup.tabs.isEmpty == false {
            return self.orderedTabs(
                self.tabGroupListTabs(
                    page: page,
                    pages: pages,
                    tabGroup: tabGroup,
                    ruleSets: ruleSets
                ),
                selectedTabId: tabGroup.selectedTabId
            )
        }

        guard let listRule: ListRule = ruleSets.listRule(id: page.ruleRefs?.list) else {
            return []
        }

        return [
            self.listTab(
                id: page.id,
                title: page.title,
                page: page,
                tabRequest: nil,
                tabContext: nil,
                listRule: listRule
            )
        ]
    }

    private func tabGroupListTabs(
        page: PageRule,
        pages: [PageRule],
        tabGroup: TabGroupRule,
        ruleSets: RuleSets
    ) -> [ListTabRule] {
        return tabGroup.tabs.compactMap { tab in
            let tabPage: PageRule = pages.first { page in
                return page.id == tab.pageRef
            } ?? page
            let listRuleID: String? = tab.listRuleRef ?? tabPage.ruleRefs?.list

            guard var listRule: ListRule = ruleSets.listRule(id: listRuleID) else {
                return nil
            }

            if let tabURL: String = tab.url,
               tabURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                listRule.url = tabURL
            }

            return self.listTab(
                id: tab.id,
                title: tab.title,
                page: tabPage,
                tabRequest: tab.request,
                tabContext: tab.context,
                listRule: listRule
            )
        }
    }

    private func listTab(
        id: String,
        title: String,
        page: PageRule,
        tabRequest: RequestConfig?,
        tabContext: ListContext?,
        listRule: ListRule
    ) -> ListTabRule {
        return ListTabRule(
            id: id,
            title: title,
            list: listRule,
            request: tabRequest ?? page.request,
            context: self.listContext(
                page: page,
                tabId: id,
                tabContext: tabContext,
                listRule: listRule
            ),
            sections: page.sections
        )
    }

    private func listContext(
        page: PageRule,
        tabId: String,
        tabContext: ListContext?,
        listRule: ListRule
    ) -> ListContext {
        var context: ListContext = tabContext ?? ListContext(
            pageId: page.id,
            tabId: tabId,
            sectionId: nil,
            listRuleId: listRule.id,
            sectionRole: .main
        )

        if context.pageId == nil {
            context.pageId = page.id
        }

        if context.tabId == nil {
            context.tabId = tabId
        }

        if context.listRuleId == nil {
            context.listRuleId = listRule.id
        }

        if context.sectionRole == nil {
            context.sectionRole = .main
        }

        return context
    }

    private func orderedTabs(_ tabs: [ListTabRule], selectedTabId: String?) -> [ListTabRule] {
        guard let selectedTabId: String = selectedTabId,
              let selectedIndex: Array<ListTabRule>.Index = tabs.firstIndex(where: { tab in
                  return tab.id == selectedTabId
              }) else {
            return tabs
        }

        var orderedTabs: [ListTabRule] = tabs
        let selectedTab: ListTabRule = orderedTabs.remove(at: selectedIndex)
        orderedTabs.insert(selectedTab, at: 0)
        return orderedTabs
    }

    /// 中文注释：列表刷新需要保留具体 tab 的页面请求配置；规则请求优先级高于页面请求，页面请求再覆盖站点共享配置。
    func request(for listTab: ListTabRule?) -> RequestConfig? {
        let listRule: ListRule = listTab?.list ?? self.primaryListRule

        return self.effectiveRequest(
            pageRequest: listTab?.request,
            ruleRequest: listRule.request
        )
    }

    /// 中文注释：P1-4.1 先完成 RequestConfig 的选择和传递，不在这里展开 headers/cookie 的深度合并。
    private func effectiveRequest(pageRequest: RequestConfig?, ruleRequest: RequestConfig?) -> RequestConfig? {
        return ruleRequest ?? pageRequest ?? self.sharedRequest
    }
}

/// 中文注释：ListRule 是 struct，负责本模块中的对应职责。
struct ListRule: Codable, Hashable {
    var id: String?
    var url: String
    /// 中文注释：V2 列表整体说明文本，例如 Pepper&Carrot 归档页的系列简介。
    var text: ExtractRule?
    var item: String
    /// 中文注释：V2 列表项规则；存在时可替代旧版 item 字符串。
    var itemRule: ExtractRule?
    /// 中文注释：V2 列表字段集合，支持发布日期、作者、分类等扩展字段。
    var fields: ListFields?
    var title: String
    var link: String
    var cover: String?
    var type: ContentType
    var latestText: String?
    var pagination: PaginationRule?
    var ready: ExtractRule?
    var request: RequestConfig?
    var js: String?
}

/// 中文注释：ListTabRule 表示首页或列表页顶部的分类入口。
struct ListTabRule: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var list: ListRule
    /// 中文注释：V2 PageRule.request 会附着在列表 tab 上，让刷新列表时知道当前页面应使用哪套请求配置。
    var request: RequestConfig? = nil
    /// 中文注释：列表 tab 的来源上下文会传给解析出的 ContentItem，P1-5.1 先记录入口，不解析 Section DOM。
    var context: ListContext? = nil
    /// 中文注释：V2 PageRule.sections 附着到 tab 上，让列表解析可以按页面区块保存来源上下文。
    var sections: [SectionRule]? = nil
}

/// 中文注释：TabGroupRule 描述同一个 V2 Page 下的多个列表入口，例如发现、更新、热门和分类。
struct TabGroupRule: Codable, Hashable {
    var id: String
    var tabs: [TabRule]
    /// 中文注释：当前 App 用第一个 ListTab 作为默认入口；这里会把 selectedTabId 对应 tab 移到默认位置。
    var selectedTabId: String?
    var layout: TabLayout?
}

/// 中文注释：TabRule 是 V2 页面内的轻量入口定义，最终会被转换成 App 既有的 ListTabRule。
struct TabRule: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var pageRef: String?
    var url: String?
    var listRuleRef: String?
    var request: RequestConfig?
    var context: ListContext?
}

enum TabLayout: String, Codable, Hashable {
    case horizontalScroll
}

/// 中文注释：DetailRule 是 struct，负责本模块中的对应职责。
struct DetailRule: Codable, Hashable {
    var id: String?
    /// 中文注释：V2 详情字段集合，用于表达标题、封面、简介、作者、标签等详情信息。
    var fields: DetailFields?
    var title: String?
    var cover: String?
    /// 中文注释：详情页主内容作用域，用于把章节解析限制在作品正文附近。
    var mainScope: ExtractRule?
    /// 中文注释：从主作用域中排除排行、推荐、广告等公共区域。
    var exclude: [ExtractRule]?
    /// 中文注释：V2 章节子规则；存在时优先于下方旧版 chapterContainer/chapterItem 字段。
    var chapterRule: ChapterRule?
    var chapterContainer: String?
    var chapterItem: String?
    var chapterTitle: String?
    var chapterLink: String?
    /// 中文注释：列表项本身就是阅读页时，跳过详情页章节抽取，直接把 detailURL 当作章节 URL。
    var treatDetailURLAsChapter: Bool?
    var tagRule: TagRule?
    var pictureRule: PictureRule?
    var commentRule: CommentRule?
    var videoRule: VideoRule?
    var ready: ExtractRule?
    var request: RequestConfig?
    var js: String?
}

/// 中文注释：ExtractRule 表示一次结构化抽取，替代旧版 selector@attr 字符串。
struct ExtractRule: Codable, Hashable {
    var selector: String?
    /// 中文注释：选择器语法类型；未指定时沿用当前 CSS/SwiftSoup 解析链路。
    var selectorKind: SelectorKind? = nil
    var function: ExtractFunction
    /// 中文注释：Yealico 风格函数链预留字段；当前解析器仍使用 function 保持兼容。
    var functions: [ExtractFunction]? = nil
    var param: String?
    var regex: String?
    var replacement: String?
    var fallback: [ExtractRule]?
}

enum SelectorKind: String, Codable, Hashable {
    case css
    case jsonPath
    case xpath
    case current
}

enum ExtractFunction: String, Codable, Hashable {
    case text
    case html
    case attr
    case raw
    case url
    case decodeBase64
    case removingPercentEncoding
    case addingPercentEncoding
    case replace
    case decompressFromBase64
    case reversed
    case regexReplacement
}

struct SectionRule: Codable, Hashable {
    var id: String?
    var title: ExtractRule?
    var role: SectionRole?
    var itemLayout: ItemLayout?
    /// 中文注释：Section 的容器节点。章节解析会按容器顺序保留源站分组顺序。
    var container: ExtractRule
    var itemRuleRef: String?
    var listRuleRef: String?
    var exclude: [ExtractRule]?
}

/// 中文注释：站点级静态配置，不直接参与 DOM 抽取。
struct SiteConfig: Codable, Hashable {
    var name: String
    var domain: String
    var baseURL: String
    var iconURL: String?
    var displayMode: DisplayMode?
    var loginURL: String?
    var language: String?
}

/// 中文注释：站点 URL 模式集合，用于路由识别和规则调试。
struct URLPatterns: Codable, Hashable {
    var series: String?
    /// 中文注释：结构化 URL 模板；未提供时继续使用上方旧版字符串字段。
    var seriesTemplate: URLTemplateRule? = nil
    var list: String?
    var listTemplate: URLTemplateRule? = nil
    var detail: String?
    var detailTemplate: URLTemplateRule? = nil
    var gallery: String?
    var galleryTemplate: URLTemplateRule? = nil
    var search: String?
    var searchTemplate: URLTemplateRule? = nil
}

/// 中文注释：URLTemplateRule 描述由占位符拼接出的 URL，用于承载分页、搜索和详情跳转模板。
struct URLTemplateRule: Codable, Hashable {
    var template: String
    /// 中文注释：显式列出模板中的占位符，便于调试器和后续执行器知道每个值的来源。
    var placeholders: [URLPlaceholderRule]?
}

struct URLPlaceholderRule: Codable, Hashable {
    var kind: URLPlaceholderKind
    /// 中文注释：自定义占位符名或查询参数名，例如 {urlQuery:chapter} 中的 chapter。
    var name: String?
    /// 中文注释：{page:start:step} 的起始页码。
    var start: Int?
    /// 中文注释：{page:start:step} 的页码步长。
    var step: Int?
    /// 中文注释：{urlPath:n} 的路径段索引。
    var index: Int?
    /// 中文注释：占位符值为空时的兜底值。
    var defaultValue: String?
    var encoding: KeywordEncoding?
}

enum URLPlaceholderKind: String, Codable, Hashable {
    case page
    case idCode
    case cidCode
    case keyword
    case url
    case urlPath
    case urlQuery
    case urlScheme
    case urlHost
    case urlPort
    case custom
}

struct PageRule: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var type: PageType
    var url: String?
    var displayMode: DisplayMode?
    var request: RequestConfig?
    /// 中文注释：页面内 tab 组用于表达同一页面下的多个列表入口，最终会展开成 ListTabRule。
    var tabGroup: TabGroupRule?
    /// 中文注释：页面内的内容区块，例如主列表、排行、推荐；P1-5.2 先用于给列表项标记来源。
    var sections: [SectionRule]? = nil
    var ruleRefs: RuleRefs?
    var flags: [PageFlag]?
}

enum PageType: String, Codable, Hashable {
    case home
    case series
    case list
    case category
    case detail
    case gallery
    case search
    case reader
}

extension PageRule {
    /// 中文注释：只有这些页面类型会作为列表入口展示；详情、阅读和搜索页先留给后续 P1-3 子任务接线。
    var isListEntryPage: Bool {
        switch self.type {
        case .home, .series, .list, .category:
            return true
        case .detail, .gallery, .search, .reader:
            return false
        }
    }

    /// 中文注释：详情入口只负责作品详情页规则，阅读页和搜索页会在后续子任务分别接入。
    var isDetailEntryPage: Bool {
        return self.type == .detail
    }

    /// 中文注释：reader/gallery 都代表可加载图片页的入口；二者共享 GalleryRule 解析正文图片。
    var isGalleryEntryPage: Bool {
        switch self.type {
        case .gallery, .reader:
            return true
        case .home, .series, .list, .category, .detail, .search:
            return false
        }
    }
}

enum DisplayMode: String, Codable, Hashable {
    case list
    case grid
    case webcomic
    case verticalReader
    case pagedReader
}

struct RuleRefs: Codable, Hashable {
    var series: String?
    var list: String?
    var detail: String?
    var gallery: String?
    var search: String?
}

struct RuleSets: Codable, Hashable {
    var seriesRules: [ListRule]?
    var listRules: [ListRule]?
    var detailRules: [DetailRule]?
    var galleryRules: [GalleryRule]?
    var searchRules: [SearchRule]?
}

extension RuleSets {
    /// 中文注释：按 rule id 查找系列页规则，后续 PageRule.ruleRefs.series 会通过这里接入 RuleSets。
    func seriesRule(id: String?) -> ListRule? {
        return Self.rule(in: self.seriesRules, id: id) { rule in
            return rule.id
        }
    }

    /// 中文注释：按 rule id 查找列表页规则，后续 PageRule.ruleRefs.list 会通过这里接入 RuleSets。
    func listRule(id: String?) -> ListRule? {
        return Self.rule(in: self.listRules, id: id) { rule in
            return rule.id
        }
    }

    /// 中文注释：按 rule id 查找详情页规则，后续 PageRule.ruleRefs.detail 会通过这里接入 RuleSets。
    func detailRule(id: String?) -> DetailRule? {
        return Self.rule(in: self.detailRules, id: id) { rule in
            return rule.id
        }
    }

    /// 中文注释：按 rule id 查找阅读页规则，后续 PageRule.ruleRefs.gallery 会通过这里接入 RuleSets。
    func galleryRule(id: String?) -> GalleryRule? {
        return Self.rule(in: self.galleryRules, id: id) { rule in
            return rule.id
        }
    }

    /// 中文注释：按 rule id 查找搜索页规则，后续 PageRule.ruleRefs.search 会通过这里接入 RuleSets。
    func searchRule(id: String?) -> SearchRule? {
        return Self.rule(in: self.searchRules, id: id) { rule in
            return rule.id
        }
    }

    /// 中文注释：统一处理空白引用和精确 id 匹配，避免各入口接线时重复写查找逻辑。
    private static func rule<T>(
        in rules: [T]?,
        id: String?,
        ruleID: (T) -> String?
    ) -> T? {
        guard let normalizedID: String = id?.trimmingCharacters(in: .whitespacesAndNewlines),
              normalizedID.isEmpty == false else {
            return nil
        }

        return rules?.first { rule in
            return ruleID(rule) == normalizedID
        }
    }
}

enum SiteFlag: String, Codable, Hashable {
    case staticHTML
    case multilingual
    case openContent
    case needsWebView
}

enum PageFlag: String, Codable, Hashable {
    case lazyImages
    case hasQualityVariants
    case hasNavigationLinks
}

/// 中文注释：V2 列表标准字段；Pepper&Carrot 这类归档页可提供 publishedAt 和 description。
struct ListFields: Codable, Hashable {
    var idCode: ExtractRule?
    var title: ExtractRule
    var cover: ExtractRule?
    var largeImage: ExtractRule?
    var video: ExtractRule?
    var detailURL: ExtractRule
    var latestText: ExtractRule?
    var description: ExtractRule?
    var coverWidth: ExtractRule?
    var coverHeight: ExtractRule?
    var category: ExtractRule?
    var author: ExtractRule?
    var uploader: ExtractRule?
    var publishedAt: ExtractRule?
    var datetime: ExtractRule?
    var rating: ExtractRule?
    var totalImages: ExtractRule?
    var language: ExtractRule?
}

/// 中文注释：V2 详情标准字段；用于承载系列简介、作者、状态、语言和版权信息。
struct DetailFields: Codable, Hashable {
    var idCode: ExtractRule?
    var title: ExtractRule?
    var cover: ExtractRule?
    var description: ExtractRule?
    var author: ExtractRule?
    var status: ExtractRule?
    var category: ExtractRule?
    var tags: ExtractRule?
    var language: ExtractRule?
    var publishedAt: ExtractRule?
    var updatedAt: ExtractRule?
    var license: ExtractRule?
    var totalImages: ExtractRule?
    /// 中文注释：指向相册或阅读页的二级页面链接，兼容 Yealico 的 photoAlbumLink 语义。
    var photoAlbumLink: ExtractRule?
    /// 中文注释：二级页面 URL 的通用命名；和 photoAlbumLink 并存，便于非相册站点表达跳转。
    var secondLevelPageURL: ExtractRule?
}

/// 中文注释：通用嵌套列表规则，可用于标签、评论、相关链接等重复结构。
struct NestedItemRule: Codable, Hashable {
    var section: SectionRule?
    var item: ExtractRule
    var idCode: ExtractRule?
    var title: ExtractRule?
    var url: ExtractRule?
    var text: ExtractRule?
    var datetime: ExtractRule?
}

/// 中文注释：标签规则使用语义化字段表达分类、标签页 URL 和展示文本，兼容旧 NestedItemRule 形状。
struct TagRule: Codable, Hashable {
    var section: SectionRule?
    var item: ExtractRule
    var idCode: ExtractRule?
    var title: ExtractRule?
    var url: ExtractRule?
    var text: ExtractRule?
    var name: ExtractRule?
}

/// 中文注释：评论规则保留头像、用户名、时间和正文等语义字段，用于区别普通嵌套列表。
struct CommentRule: Codable, Hashable {
    var section: SectionRule?
    var item: ExtractRule
    var idCode: ExtractRule?
    var avatar: ExtractRule?
    var username: ExtractRule?
    var datetime: ExtractRule?
    var content: ExtractRule?
    var url: ExtractRule?
    var title: ExtractRule?
    var text: ExtractRule?
}

/// 中文注释：图片或媒体资源规则；详情页插图、相关图、视频封面可复用。
struct PictureRule: Codable, Hashable {
    var section: SectionRule?
    var item: ExtractRule
    var image: ExtractRule
    var thumbnail: ExtractRule?
    var link: ExtractRule?
    var title: ExtractRule?
    var width: ExtractRule?
    var height: ExtractRule?
}

enum SectionRole: String, Codable, Hashable {
    case main
    case ranking
    case recommendation
    case category
}

enum ItemLayout: String, Codable, Hashable {
    case horizontalRow
    case verticalGrid
}

struct ChapterRule: Codable, Hashable {
    var section: SectionRule?
    var item: ExtractRule
    /// 中文注释：章节稳定标识抽取规则；可从结构化数据中读取 id 并拼出章节 URL。
    var idCode: ExtractRule?
    /// 中文注释：cidCode 是章节级 idCode 的显式别名，用于填充 {cidCode:} URL 占位符。
    var cidCode: ExtractRule?
    var title: ExtractRule
    var url: ExtractRule
    var datetime: ExtractRule?
    var language: ExtractRule?
    var index: ExtractRule?
    var sort: ChapterSort?
    /// 中文注释：预留字段，用于要求章节组必须包含列表卡片上的 latestText，避免匹配到推荐区。
    var mustMatchLatestText: Bool?
}

enum ChapterSort: String, Codable, Hashable {
    case ascending
    case descending
    case none
}

/// 中文注释：GalleryRule 是 struct，负责本模块中的对应职责。
struct GalleryRule: Codable, Hashable {
    var id: String?
    /// 中文注释：阅读页主作用域，例如 Pepper&Carrot 的 .container.webcomic。
    var mainScope: ExtractRule?
    /// 中文注释：V2 页图节点规则；存在时可替代旧版 imageItem 字符串。
    var item: ExtractRule?
    /// 中文注释：V2 页图 URL 抽取规则；存在时可替代旧版 imageUrl 字符串。
    var image: ExtractRule?
    var thumbnail: ExtractRule?
    var link: ExtractRule?
    var totalPages: ExtractRule?
    var secondLevelPageURL: ExtractRule?
    /// 中文注释：阅读页质量/模式切换入口，例如普通、高清、双语对照。
    var variants: [GalleryVariantRule]?
    /// 中文注释：源文件、制作包、相关下载等资源链接，不直接作为阅读图片。
    var sourceFiles: [ResourceLinkRule]?
    var pagination: PaginationRule?
    var request: RequestConfig?
    var js: String?
    var imageItem: String
    var imageUrl: String
    var comicTitle: String?
    var chapterTitle: String?
    var catalogLink: String?
    var previousLink: String?
    var nextLink: String?
}

struct GalleryVariantRule: Codable, Hashable {
    var id: String
    var title: String?
    var url: ExtractRule
    var isDefault: Bool?
}

struct ResourceLinkRule: Codable, Hashable {
    var id: String?
    var title: ExtractRule?
    var url: ExtractRule
    var fileType: ExtractRule?
    var fileSize: ExtractRule?
}

struct SearchRule: Codable, Hashable {
    var id: String?
    var keywordEncoding: KeywordEncoding?
    var url: String
    var method: HTTPMethod?
    var request: RequestConfig?
    var listRuleRef: String?
    var item: ExtractRule
    var fields: ListFields
    var pagination: PaginationRule?
}

enum KeywordEncoding: String, Codable, Hashable {
    case urlQueryAllowed
    case percentEncoded
    case raw
}

struct PaginationRule: Codable, Hashable {
    var nextPage: ExtractRule?
    var pagePlaceholder: String?
    var maxPages: Int?
    var stopWhenEmpty: Bool?
}

struct RequestConfig: Codable, Hashable {
    /// 中文注释：请求配置所在层级，用于调试 Rule > Page > Site sharedRequest 的继承来源。
    var scope: RequestScope?
    /// 中文注释：声明当前请求配置如何与父级配置合并；未指定时由旧执行流保持原行为。
    var mergePolicy: RequestMergePolicy?
    var method: HTTPMethod?
    var headers: [String: String]?
    var body: RequestBody?
    var cookiePolicy: CookiePolicy?
    /// 中文注释：当浏览器 Cookie、自定义 Cookie 和规则 Cookie 同时存在时，明确优先使用哪一类。
    var cookiePriority: CookiePriority?
    /// 中文注释：限制 Cookie 的保存或复用范围，避免站点、页面、图片请求之间互相污染。
    var cookieScope: CookieScope?
    var charset: Charset?
    var needsWebView: Bool?
    var autoScroll: Bool?
    var imageHeaders: [String: String]?
    /// 中文注释：图片加载可拥有独立请求配置，例如 referer、accept、cookie 优先级。
    var imageRequest: ImageRequestConfig?
}

enum RequestScope: String, Codable, Hashable {
    case site
    case page
    case rule
    case image
    case search
    case reader
}

enum RequestMergePolicy: String, Codable, Hashable {
    case inherit
    case override
    case mergeHeaders
    case mergeHeadersAndCookies
}

struct ImageRequestConfig: Codable, Hashable {
    var headers: [String: String]?
    var cookiePolicy: CookiePolicy?
    var cookiePriority: CookiePriority?
    var cookieScope: CookieScope?
    var mergePolicy: RequestMergePolicy?
}

enum HTTPMethod: String, Codable, Hashable {
    case get = "GET"
    case post = "POST"
}

struct RequestBody: Codable, Hashable {
    var contentType: String?
    var value: String
}

enum CookiePolicy: String, Codable, Hashable {
    case none
    case browser
    case custom
    case browserThenCustom
}

enum CookiePriority: String, Codable, Hashable {
    case none
    case browser
    case custom
    case request
    case image
}

enum CookieScope: String, Codable, Hashable {
    case none
    case session
    case persistent
    case site
    case page
    case rule
    case image
}

enum Charset: String, Codable, Hashable {
    case utf8
    case gb18030
    case shiftJIS
    case auto
}

/// 中文注释：VideoRule 兼容旧版 videoUrl，并支持 Yealico 风格 item/thumbnail/url/link 视频字段。
struct VideoRule: Codable, Hashable {
    var videoUrl: String? = nil
    var section: SectionRule? = nil
    var item: ExtractRule? = nil
    var url: ExtractRule? = nil
    var thumbnail: ExtractRule? = nil
    var link: ExtractRule? = nil
    var title: ExtractRule? = nil
    var duration: ExtractRule? = nil
    var width: ExtractRule? = nil
    var height: ExtractRule? = nil
}

extension SiteRule {
    /// 中文注释：AddSourceView 展示给用户参考的规则 JSON 示例。
    static let exampleJSON: String = """
    {
      "name": "Example Site",
      "baseUrl": "https://example.com",
      "list": {
        "url": "https://example.com/list/{page}",
        "item": ".card",
        "title": ".title",
        "link": ".title@href",
        "cover": "img@src",
        "type": "comic",
        "latestText": ".badge"
      },
      "detail": {
        "title": "h1",
        "cover": ".cover img@src",
        "chapterContainer": ".chapter-list",
        "chapterItem": ".chapter-list a",
        "chapterTitle": "this",
        "chapterLink": "this@href"
      },
      "gallery": {
        "imageItem": ".reader img",
        "imageUrl": "this@src"
      },
      "video": {
        "videoUrl": "video@src"
      }
    }
    """

    /// Built-in production rules live in the private BrowseCraftRulesKit package.
    /// Keep this public example generic so the app shell can be published safely.
}
