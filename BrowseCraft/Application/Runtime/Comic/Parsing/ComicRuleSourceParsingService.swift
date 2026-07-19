import Foundation

// 中文注释：ComicRuleSourceParsingService 属于 ComicSourceRuntime 的解析边界，只服务 SiteRule-backed source。

/// 中文注释：漫画规则详情解析的内部标准化元数据；它隔离 DOM/API 字段，不跨越 SourceRuntime 公共边界。
struct ComicRuleParsedDetailMetadata: Hashable {
    var idCode: String?
    var title: String?
    var coverURL: String?
    var description: String?
    var author: String?
    var status: String?
    var category: String?
    var tags: [String]
    var language: String?
    var publishedAt: String?
    var updatedAt: String?
    var license: String?
    var totalImages: Int?
    var photoAlbumURL: String?
    var secondLevelPageURL: String?

    init(
        idCode: String? = nil,
        title: String? = nil,
        coverURL: String? = nil,
        description: String? = nil,
        author: String? = nil,
        status: String? = nil,
        category: String? = nil,
        tags: [String] = [],
        language: String? = nil,
        publishedAt: String? = nil,
        updatedAt: String? = nil,
        license: String? = nil,
        totalImages: Int? = nil,
        photoAlbumURL: String? = nil,
        secondLevelPageURL: String? = nil
    ) {
        self.idCode = idCode
        self.title = title
        self.coverURL = coverURL
        self.description = description
        self.author = author
        self.status = status
        self.category = category
        self.tags = tags
        self.language = language
        self.publishedAt = publishedAt
        self.updatedAt = updatedAt
        self.license = license
        self.totalImages = totalImages
        self.photoAlbumURL = photoAlbumURL
        self.secondLevelPageURL = secondLevelPageURL
    }
}

/// 中文注释：解析 adapter 的完整详情输出；loader 只负责请求和 DOM/API 编排。
struct ComicRuleParsedDetail: Hashable {
    var metadata: ComicRuleParsedDetailMetadata
    var chapters: [ChapterLink]

    init(
        metadata: ComicRuleParsedDetailMetadata = ComicRuleParsedDetailMetadata(),
        chapters: [ChapterLink]
    ) {
        self.metadata = metadata
        self.chapters = chapters
    }

    /// 中文注释：兼容第一阶段调用点，后续调用应优先传完整 metadata。
    init(chapters: [ChapterLink], description: String?) {
        self.init(
            metadata: ComicRuleParsedDetailMetadata(description: description),
            chapters: chapters
        )
    }

    var description: String? {
        get { return self.metadata.description }
        set { self.metadata.description = newValue }
    }
}

// 中文注释：仅兼容 loader 级测试名称；跨 runtime 的详情类型始终是 Core SourceDetailOutput。
typealias ChapterDetailContent = ComicRuleParsedDetail

/// 中文注释：ComicSourceRuntime 专用解析协议，把原始页面文档转换成应用内部统一模型。
/// 中文注释：生产环境目前用 SwiftSoup 解析 HTML，但上层只依赖这个协议，方便以后替换解析器。
protocol ComicRuleSourceParsingService {
    /// 中文注释：parseList 方法封装当前类型的一段业务或界面行为。
    func parseList(html: String, source: Source) throws -> [ContentItem]
    func parseList(html: String, source: Source, listRule: ListRule) throws -> [ContentItem]
    func parseList(
        html: String,
        source: Source,
        listRule: ListRule,
        context: ListContext?,
        sections: [SectionRule]?
    ) throws -> [ContentItem]
    func parseSearch(
        html: String,
        source: Source,
        searchRule: SearchRule,
        context: ListContext?
    ) throws -> [ContentItem]
    /// 中文注释：parseDetailChapters 方法封装当前类型的一段业务或界面行为。
    func parseDetailChapters(html: String, source: Source, pageURL: String) throws -> [ChapterLink]
    func parseDetailChapters(
        html: String,
        source: Source,
        pageURL: String,
        context: ListContext?
    ) throws -> [ChapterLink]
    func parseDetailChapters(
        html: String,
        source: Source,
        detailRule: DetailRule,
        pageURL: String,
        context: ListContext?
    ) throws -> [ChapterLink]
    func parseDetail(
        html: String,
        source: Source,
        detailRule: DetailRule,
        pageURL: String,
        context: ListContext?
    ) throws -> ComicRuleParsedDetail
    func parseDetailDescription(
        html: String,
        source: Source,
        detailRule: DetailRule,
        pageURL: String,
        context: ListContext?
    ) throws -> String?
    /// 中文注释：parseReader 方法封装当前类型的一段业务或界面行为。
    func parseReader(html: String, source: Source, pageURL: String) throws -> ReaderChapter
    func parseReader(
        html: String,
        source: Source,
        pageURL: String,
        context: ListContext?
    ) throws -> ReaderChapter
    func parseReader(
        html: String,
        source: Source,
        galleryRule: GalleryRule,
        pageURL: String,
        context: ListContext?
    ) throws -> ReaderChapter
}

/// 中文注释：分页解析结果只描述“下一步可以请求哪里”，不触发自动翻页。
struct PaginationResolution: Hashable {
    var currentPage: Int
    var nextPage: Int?
    var nextURL: String?
    var source: PaginationResolutionSource?
}

enum PaginationResolutionSource: String, Hashable {
    case pagePlaceholder
    case nextPageLink
}

/// 中文注释：支持 DOM 的解析器可额外实现 nextPage 抽取，UseCase 不直接依赖具体 HTML 解析库。
protocol ComicRulePaginationParsingService {
    func parseNextPageURL(
        html: String,
        source: Source,
        pagination: PaginationRule,
        currentURL: URL
    ) throws -> String?
}

extension ComicRuleSourceParsingService {
    /// 中文注释：P1-5.1 先在解析结果上附加列表上下文；具体 Section DOM 拆分留到后续步骤。
    func parseList(html: String, source: Source, listRule: ListRule, context: ListContext?) throws -> [ContentItem] {
        return try self.parseList(
            html: html,
            source: source,
            listRule: listRule,
            context: context,
            sections: nil
        )
    }

    /// 中文注释：P1-5.2 增加 sections 参数；默认实现不解析区块，具体解析器可覆盖为 section-aware 行为。
    func parseList(
        html: String,
        source: Source,
        listRule: ListRule,
        context: ListContext?,
        sections: [SectionRule]?
    ) throws -> [ContentItem] {
        let items: [ContentItem] = try self.parseList(
            html: html,
            source: source,
            listRule: listRule
        )

        return items.map { item in
            var contextualItem: ContentItem = item
            contextualItem.listContext = context
            return contextualItem
        }
    }

    /// 中文注释：P2-6.2 为搜索增加显式解析入口；默认回落到引用的 ListRule，避免一次性改动所有测试替身。
    func parseSearch(
        html: String,
        source: Source,
        searchRule: SearchRule,
        context: ListContext?
    ) throws -> [ContentItem] {
        if let listRule: ListRule = source.rule.ruleSets?.listRule(id: searchRule.listRuleRef) {
            return try self.parseList(
                html: html,
                source: source,
                listRule: listRule,
                context: context
            )
        }

        return try self.parseList(
            html: html,
            source: source,
            listRule: source.rule.primaryListRule,
            context: context
        )
    }

    /// 中文注释：P1-5.3 默认保持旧解析行为；支持上下文的解析器可覆盖并按来源区块缩小 Detail 作用域。
    func parseDetailChapters(
        html: String,
        source: Source,
        pageURL: String,
        context: ListContext?
    ) throws -> [ChapterLink] {
        return try self.parseDetailChapters(
            html: html,
            source: source,
            pageURL: pageURL
        )
    }

    /// 中文注释：兼容尚未实现完整详情解析的测试替身；生产 SwiftSoup adapter 会覆盖并只解析一次文档。
    func parseDetail(
        html: String,
        source: Source,
        detailRule: DetailRule,
        pageURL: String,
        context: ListContext?
    ) throws -> ComicRuleParsedDetail {
        let chapters: [ChapterLink] = try self.parseDetailChapters(
            html: html,
            source: source,
            detailRule: detailRule,
            pageURL: pageURL,
            context: context
        )
        let description: String? = try self.parseDetailDescription(
            html: html,
            source: source,
            detailRule: detailRule,
            pageURL: pageURL,
            context: context
        )

        return ComicRuleParsedDetail(chapters: chapters, description: description)
    }

    /// 中文注释：P2-5.3 新增显式规则入口；默认回落到旧入口，避免一次性改动所有测试替身。
    func parseDetailChapters(
        html: String,
        source: Source,
        detailRule: DetailRule,
        pageURL: String,
        context: ListContext?
    ) throws -> [ChapterLink] {
        return try self.parseDetailChapters(
            html: html,
            source: source,
            pageURL: pageURL,
            context: context
        )
    }

    func parseDetailDescription(
        html: String,
        source: Source,
        detailRule: DetailRule,
        pageURL: String,
        context: ListContext?
    ) throws -> String? {
        return nil
    }

    /// 中文注释：P1-5.3 默认保持旧解析行为；支持上下文的解析器可覆盖并按来源区块缩小 Reader 作用域。
    func parseReader(
        html: String,
        source: Source,
        pageURL: String,
        context: ListContext?
    ) throws -> ReaderChapter {
        return try self.parseReader(
            html: html,
            source: source,
            pageURL: pageURL
        )
    }

    /// 中文注释：P2-5.3 新增显式规则入口；默认回落到旧入口，避免一次性改动所有测试替身。
    func parseReader(
        html: String,
        source: Source,
        galleryRule: GalleryRule,
        pageURL: String,
        context: ListContext?
    ) throws -> ReaderChapter {
        return try self.parseReader(
            html: html,
            source: source,
            pageURL: pageURL,
            context: context
        )
    }
}
