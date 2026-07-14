import Foundation

// 中文注释：ComicRuleSourceChapterLoader 是 ComicRuleSourceRuntime 内部章节目录加载边界，只处理 SiteRule-backed source。

/// 中文注释：LoadChaptersError 是 enum，负责本模块中的对应职责。
enum LoadChaptersError: LocalizedError {
    case noChaptersFound(detailURLString: String)

    var errorDescription: String? {
        switch self {
        case .noChaptersFound(let detailURLString):
            return "No chapter link was found on detail page: \(detailURLString)"
        }
    }
}

/// 中文注释：加载单个 Library 条目的章节目录。
struct ComicRuleSourceChapterLoader {
    private let pageContentLoader: PageContentLoader
    private let comicRuleParser: ComicRuleSourceParsingService

    init(
        pageContentLoader: PageContentLoader,
        comicRuleParser: ComicRuleSourceParsingService
    ) {
        self.pageContentLoader = pageContentLoader
        self.comicRuleParser = comicRuleParser
    }

    /// 中文注释：兼容旧测试和旧装配入口；普通 HTTP 客户端继续可直接作为页面内容加载器使用。
    init(
        httpClient: HTTPClient,
        comicRuleParser: ComicRuleSourceParsingService
    ) {
        self.init(
            pageContentLoader: httpClient,
            comicRuleParser: comicRuleParser
        )
    }

    /// 中文注释：execute 方法封装当前类型的一段业务或界面行为。
    func execute(source: Source, item: ContentItem) async throws -> ChapterDetailContent {
        let resolvedRule: ResolvedSiteRule = RuleResolver().resolve(source.rule)

        RuleExecutionLogger.log(
            stage: .detail,
            event: "request",
            fields: [
                "source": source.id,
                "item": item.id,
                "tab": item.listContext?.tabId ?? "nil",
                "section": item.listContext?.sectionId ?? "nil",
                "listRule": item.listContext?.listRuleId ?? "nil",
                "detailURL": item.detailURL,
                "latestText": item.latestText ?? "nil"
            ]
        )

        if shouldTreatDetailURLAsChapter(resolvedRule: resolvedRule, item: item) {
            RuleExecutionLogger.log(
                stage: .detail,
                event: "direct-chapter",
                fields: [
                    "source": source.id,
                    "item": item.id,
                    "detailURL": item.detailURL
                ]
            )

            return ChapterDetailContent(
                chapters: [
                    ChapterLink(
                        title: item.latestText ?? item.title,
                        url: item.detailURL
                    )
                ],
                description: nil
            )
        }

        guard let detailURL: URL = URL(string: item.detailURL) else {
            throw RuleExecutionError.ruleConfiguration(
                stage: .detail,
                sourceID: source.id,
                reason: "Invalid detail URL: \(item.detailURL)"
            )
        }

        let detailHTML: String = try await self.pageContentLoader.getString(
            from: detailURL,
            request: resolvedRule.primaryDetailRequest
        )
        let chapters: [ChapterLink]
        let description: String?
        if let detailRule: DetailRule = resolvedRule.primaryDetailRule {
            chapters = try self.comicRuleParser.parseDetailChapters(
                html: detailHTML,
                source: source,
                detailRule: detailRule,
                pageURL: item.detailURL,
                context: item.listContext
            )
            description = try self.comicRuleParser.parseDetailDescription(
                html: detailHTML,
                source: source,
                detailRule: detailRule,
                pageURL: item.detailURL,
                context: item.listContext
            )
        } else {
            chapters = []
            description = nil
        }

        RuleExecutionLogger.log(
            stage: .detail,
            event: "parsed",
            fields: [
                "source": source.id,
                "item": item.id,
                "detailURL": item.detailURL,
                "count": chapters.count,
                "firstURL": chapters.first?.url ?? "nil"
            ]
        )

        if chapters.isEmpty {
            throw RuleExecutionError.selectorEmpty(
                stage: .detail,
                sourceID: source.id,
                url: item.detailURL,
                ruleID: resolvedRule.detailEntry?.ruleID
            )
        }

        return ChapterDetailContent(
            chapters: chapters,
            description: description
        )
    }
}

func shouldTreatDetailURLAsChapter(resolvedRule: ResolvedSiteRule, item: ContentItem) -> Bool {
    if item.detailURL.contains("/chapters/") {
        return true
    }

    return resolvedRule.treatsDetailURLAsChapter
}
