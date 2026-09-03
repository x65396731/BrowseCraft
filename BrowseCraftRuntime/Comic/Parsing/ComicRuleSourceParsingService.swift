import BrowseCraftCore
import BrowseCraftDomain
import Foundation

// 中文注释：ComicRuleSourceParsingService 属于 ComicSourceRuntime 的解析边界，只服务 SiteRule-backed source。

/// 中文注释：漫画规则详情解析的内部标准化元数据；它隔离 DOM/API 字段，不跨越 SourceRuntime 公共边界。
public struct ComicRuleParsedDetailMetadata: Hashable, Sendable {
    public var idCode: String?
    public var title: String?
    public var coverURL: String?
    public var description: String?
    public var author: String?
    public var status: String?
    public var category: String?
    public var tags: [String]
    public var language: String?
    public var publishedAt: String?
    public var updatedAt: String?
    public var license: String?
    public var totalImages: Int?
    public var photoAlbumURL: String?
    public var secondLevelPageURL: String?

    public init(
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
public struct ComicRuleParsedDetail: Hashable, Sendable {
    public var metadata: ComicRuleParsedDetailMetadata
    public var chapters: [ChapterLink]

    public init(
        metadata: ComicRuleParsedDetailMetadata = ComicRuleParsedDetailMetadata(),
        chapters: [ChapterLink]
    ) {
        self.metadata = metadata
        self.chapters = chapters
    }

    public var description: String? {
        get { return self.metadata.description }
        set { self.metadata.description = newValue }
    }
}

/// 中文注释：列表/搜索解析结果同时携带 Core 解析出的分页语义，Loader 只负责生成下一次请求。
public struct ComicRuleParsedListResult: Hashable, Sendable {
    public init(
        items: [ContentItem],
        pagination: PaginationResolution? = nil
    ) {
        self.items = items
        self.pagination = pagination
    }

    public var items: [ContentItem]
    public var pagination: PaginationResolution?
}

/// 中文注释：ComicSourceRuntime 专用解析协议；App 只传入已加载文档，确定性规则解释统一由 Core 完成。
public protocol ComicRuleSourceParsingService: ComicRuleAPIResponseParsingService, Sendable {
    func parseList(
        html: String,
        source: Source,
        resolvedRule: ResolvedComicSiteRuleV2,
        entry: ResolvedComicListEntry,
        pageURL: URL,
        currentPage: Int?
    ) throws -> [ContentItem]
    func parseSearchResult(
        html: String,
        source: Source,
        resolvedRule: ResolvedComicSiteRuleV2,
        entry: ResolvedComicSearchEntry,
        pageURL: URL,
        currentPage: Int?
    ) throws -> ComicRuleParsedListResult
    func parseDetail(
        html: String,
        source: Source,
        resolvedRule: ResolvedComicSiteRuleV2,
        entry: ResolvedComicDetailEntry,
        item: ContentItem,
        pageURL: String
    ) throws -> ComicRuleParsedDetail
    func parseReader(
        html: String,
        source: Source,
        resolvedRule: ResolvedComicSiteRuleV2,
        entry: ResolvedComicReaderEntry,
        item: ContentItem,
        pageURL: String
    ) throws -> ReaderChapter
}

/// 中文注释：API 请求仍由 Loader 执行；实现此能力的 parser 只消费已经取得的 JSON 响应。
public protocol ComicRuleAPIResponseParsingService: Sendable {
    func parseListAPIResponse(
        json: String,
        finalURL: URL,
        source: Source,
        resolvedRule: ResolvedComicSiteRuleV2,
        entry: ResolvedComicListEntry,
        sectionBinding: ResolvedComicSectionBinding?,
        templateItem: ContentItem,
        listPageURL: URL,
        currentPage: Int?
    ) throws -> [ContentItem]

    func parseChapterAPIResponse(
        json: String,
        finalURL: URL,
        source: Source,
        resolvedRule: ResolvedComicSiteRuleV2,
        entry: ResolvedComicDetailEntry,
        item: ContentItem
    ) throws -> ComicRuleParsedDetail

    func parseImageAPIResponse(
        json: String,
        finalURL: URL,
        source: Source,
        resolvedRule: ResolvedComicSiteRuleV2,
        entry: ResolvedComicReaderEntry,
        item: ContentItem,
        chapterURL: URL,
        chapterFinalURL: URL?
    ) throws -> ReaderChapter
}

/// 中文注释：分页解析结果只描述“下一步可以请求哪里”，不触发自动翻页。
public struct PaginationResolution: Hashable, Sendable {
    public init(
        currentPage: Int,
        nextPage: Int? = nil,
        nextURL: String? = nil,
        source: PaginationResolutionSource? = nil
    ) {
        self.currentPage = currentPage
        self.nextPage = nextPage
        self.nextURL = nextURL
        self.source = source
    }

    public var currentPage: Int
    public var nextPage: Int?
    public var nextURL: String?
    public var source: PaginationResolutionSource?
}

public enum PaginationResolutionSource: String, Hashable, Sendable {
    case pagePlaceholder
    case nextPageLink
}

public extension ComicRuleSourceParsingService {
    func parseDetailChapters(
        html: String,
        source: Source,
        resolvedRule: ResolvedComicSiteRuleV2,
        entry: ResolvedComicDetailEntry,
        item: ContentItem,
        pageURL: String
    ) throws -> [ChapterLink] {
        return try self.parseDetail(
            html: html,
            source: source,
            resolvedRule: resolvedRule,
            entry: entry,
            item: item,
            pageURL: pageURL
        ).chapters
    }
}
