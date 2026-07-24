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

/// 中文注释：列表/搜索解析结果同时携带 Core 解析出的分页语义，Loader 只负责生成下一次请求。
struct ComicRuleParsedListResult: Hashable {
    var items: [ContentItem]
    var pagination: PaginationResolution?
}

/// 中文注释：ComicSourceRuntime 专用解析协议；App 只传入已加载文档，确定性规则解释统一由 Core 完成。
protocol ComicRuleSourceParsingService: ComicRuleAPIResponseParsingService {
    func parseList(
        html: String,
        source: Source,
        listRule: ListRule,
        context: ListContext?,
        sections: [SectionRule]?,
        pageURL: URL,
        currentPage: Int?
    ) throws -> [ContentItem]
    func parseSearchResult(
        html: String,
        source: Source,
        searchRule: SearchRule,
        context: ListContext?,
        pageURL: URL,
        currentPage: Int?
    ) throws -> ComicRuleParsedListResult
    func parseDetail(
        html: String,
        source: Source,
        detailRule: DetailRule,
        pageURL: String,
        context: ListContext?
    ) throws -> ComicRuleParsedDetail
    func parseReader(
        html: String,
        source: Source,
        galleryRule: GalleryRule,
        pageURL: String,
        context: ListContext?
    ) throws -> ReaderChapter
}

/// 中文注释：API 请求仍由 Loader 执行；实现此能力的 parser 只消费已经取得的 JSON 响应。
protocol ComicRuleAPIResponseParsingService {
    func parseListAPIResponse(
        json: String,
        finalURL: URL,
        source: Source,
        templateItem: ContentItem,
        apiRule: ListAPIRule,
        listPageURL: URL,
        currentPage: Int?,
        context: ListContext?
    ) throws -> [ContentItem]

    func parseChapterAPIResponse(
        json: String,
        finalURL: URL,
        source: Source,
        item: ContentItem,
        apiRule: DetailChapterAPIRule,
        context: ListContext?
    ) throws -> ComicRuleParsedDetail

    func parseImageAPIResponse(
        json: String,
        finalURL: URL,
        source: Source,
        item: ContentItem,
        apiRule: ReaderImageAPIRule,
        chapterURL: URL,
        chapterFinalURL: URL?,
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

extension ComicRuleSourceParsingService {
    func parseDetailChapters(
        html: String,
        source: Source,
        detailRule: DetailRule,
        pageURL: String,
        context: ListContext?
    ) throws -> [ChapterLink] {
        return try self.parseDetail(
            html: html,
            source: source,
            detailRule: detailRule,
            pageURL: pageURL,
            context: context
        ).chapters
    }
}
