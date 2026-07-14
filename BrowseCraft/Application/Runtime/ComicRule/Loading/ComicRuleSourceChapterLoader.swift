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
    private struct ZaiManhuaDetailResponse: Decodable {
        let errno: Int
        let data: ZaiManhuaDetailData?
    }

    private struct ZaiManhuaDetailData: Decodable {
        let comicInfo: ZaiManhuaComicInfo?
    }

    private struct ZaiManhuaComicInfo: Decodable {
        let id: Int
        let comicPy: String
        let description: String?
        let chapterList: [ZaiManhuaChapterGroup]?
    }

    private struct ZaiManhuaChapterGroup: Decodable {
        let title: String?
        let data: [ZaiManhuaChapter]
    }

    private struct ZaiManhuaChapter: Decodable {
        let chapterID: Int
        let chapterTitle: String
        let chapterOrder: Int?

        enum CodingKeys: String, CodingKey {
            case chapterID = "chapter_id"
            case chapterTitle = "chapter_title"
            case chapterOrder = "chapter_order"
        }
    }

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
            let parsedChapters: [ChapterLink] = try self.comicRuleParser.parseDetailChapters(
                html: detailHTML,
                source: source,
                detailRule: detailRule,
                pageURL: item.detailURL,
                context: item.listContext
            )
            let parsedDescription: String? = try self.comicRuleParser.parseDetailDescription(
                html: detailHTML,
                source: source,
                detailRule: detailRule,
                pageURL: item.detailURL,
                context: item.listContext
            )

            if self.shouldUseZaiManhuaDetailAPI(source: source, item: item, chapters: parsedChapters),
               let apiDetail: ChapterDetailContent = try await self.loadZaiManhuaDetailAPI(source: source, item: item) {
                chapters = apiDetail.chapters
                description = apiDetail.description ?? parsedDescription
            } else {
                chapters = parsedChapters
                description = parsedDescription
            }
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

    private func shouldUseZaiManhuaDetailAPI(source: Source, item: ContentItem, chapters: [ChapterLink]) -> Bool {
        guard source.baseURL.contains("zaimanhua.com"),
              item.detailURL.contains("/info/") else {
            return false
        }

        if chapters.isEmpty {
            return true
        }

        return chapters.contains { chapter in
            return chapter.url.contains("/view/undefined/")
        }
    }

    private func loadZaiManhuaDetailAPI(source: Source, item: ContentItem) async throws -> ChapterDetailContent? {
        guard let comicPy: String = self.zaiManhuaComicPy(from: item.detailURL),
              var components: URLComponents = URLComponents(string: "https://www.zaimanhua.com/api/v1/comic1/comic/detail") else {
            return nil
        }

        components.queryItems = [
            URLQueryItem(name: "channel", value: "pc"),
            URLQueryItem(name: "app_name", value: "zmh"),
            URLQueryItem(name: "version", value: "1.0.0"),
            URLQueryItem(name: "timestamp", value: String(Int(Date().timeIntervalSince1970))),
            URLQueryItem(name: "uid", value: "113119197"),
            URLQueryItem(name: "comic_py", value: comicPy)
        ]

        guard let apiURL: URL = components.url else {
            return nil
        }

        RuleExecutionLogger.log(
            stage: .detail,
            event: "zaimanhua-api-request",
            fields: [
                "source": source.id,
                "item": item.id,
                "apiURL": apiURL.absoluteString
            ]
        )

        let json: String = try await self.pageContentLoader.getString(
            from: apiURL,
            request: nil
        )
        let response: ZaiManhuaDetailResponse = try JSONDecoder().decode(
            ZaiManhuaDetailResponse.self,
            from: Data(json.utf8)
        )

        guard response.errno == 0,
              let comicInfo: ZaiManhuaComicInfo = response.data?.comicInfo else {
            return nil
        }

        let chapters: [ChapterLink] = self.zaiManhuaChapters(from: comicInfo)
        RuleExecutionLogger.log(
            stage: .detail,
            event: "zaimanhua-api-parsed",
            fields: [
                "source": source.id,
                "item": item.id,
                "comicID": comicInfo.id,
                "chapterCount": chapters.count,
                "firstURL": chapters.first?.url ?? "nil"
            ]
        )

        guard chapters.isEmpty == false else {
            return nil
        }

        return ChapterDetailContent(
            chapters: chapters,
            description: comicInfo.description
        )
    }

    private func zaiManhuaComicPy(from detailURL: String) -> String? {
        guard let url: URL = URL(string: detailURL) else {
            return nil
        }

        let lastPathComponent: String = url.lastPathComponent
        guard lastPathComponent.hasSuffix(".html") else {
            return nil
        }

        return String(lastPathComponent.dropLast(".html".count))
    }

    private func zaiManhuaChapters(from comicInfo: ZaiManhuaComicInfo) -> [ChapterLink] {
        var chapters: [ChapterLink] = []
        var seenURLs: Set<String> = Set<String>()

        for group: ZaiManhuaChapterGroup in comicInfo.chapterList ?? [] {
            for chapter: ZaiManhuaChapter in group.data {
                let url: String = "https://www.zaimanhua.com/view/\(comicInfo.comicPy)/\(comicInfo.id)/\(chapter.chapterID)"
                guard seenURLs.contains(url) == false else {
                    continue
                }

                seenURLs.insert(url)
                chapters.append(
                    ChapterLink(
                        title: chapter.chapterTitle,
                        url: url
                    )
                )
            }
        }

        return chapters.sorted { lhs, rhs in
            guard let lhsOrder: Int = self.zaiManhuaChapterOrder(chapter: lhs, comicInfo: comicInfo),
                  let rhsOrder: Int = self.zaiManhuaChapterOrder(chapter: rhs, comicInfo: comicInfo) else {
                return false
            }

            return lhsOrder > rhsOrder
        }
    }

    private func zaiManhuaChapterOrder(chapter: ChapterLink, comicInfo: ZaiManhuaComicInfo) -> Int? {
        for group: ZaiManhuaChapterGroup in comicInfo.chapterList ?? [] {
            for sourceChapter: ZaiManhuaChapter in group.data {
                let url: String = "https://www.zaimanhua.com/view/\(comicInfo.comicPy)/\(comicInfo.id)/\(sourceChapter.chapterID)"
                if chapter.url == url {
                    return sourceChapter.chapterOrder
                }
            }
        }

        return nil
    }
}

func shouldTreatDetailURLAsChapter(resolvedRule: ResolvedSiteRule, item: ContentItem) -> Bool {
    if item.detailURL.contains("/chapters/") {
        return true
    }

    return resolvedRule.treatsDetailURLAsChapter
}
