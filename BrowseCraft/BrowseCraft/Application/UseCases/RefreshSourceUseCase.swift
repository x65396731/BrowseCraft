import Foundation

// 中文注释：RefreshSourceUseCase.swift 属于应用用例层，用于说明本文件承载的核心职责。

/// 中文注释：抓取源站列表页，解析为标准条目，保存后返回结果。
/// 中文注释：核心流程是 Source + Rule -> Fetch -> Parse -> Normalize -> Store -> Display。
struct RefreshSourceUseCase {
    private let httpClient: HTTPClient
    private let ruleParser: RuleParsingService
    private let urlResolver: URLResolvingService
    private let contentRepository: ContentRepository

    init(
        httpClient: HTTPClient,
        ruleParser: RuleParsingService,
        urlResolver: URLResolvingService,
        contentRepository: ContentRepository
    ) {
        self.httpClient = httpClient
        self.ruleParser = ruleParser
        self.urlResolver = urlResolver
        self.contentRepository = contentRepository
    }

    /// 中文注释：execute 方法封装当前类型的一段业务或界面行为。
    func execute(source: Source, page: Int = 1) async throws -> [ContentItem] {
        return try await self.execute(source: source, listTab: source.rule.availableListTabs.first, page: page)
    }

    func execute(source: Source, listTab: ListTabRule?, page: Int = 1) async throws -> [ContentItem] {
        let listRule: ListRule = listTab?.list ?? source.rule.list
        let url: URL = try self.urlResolver.listURL(for: source, listRule: listRule, page: page)

        #if DEBUG
        print(
            "[BrowseCraftNavigation] Refresh list " +
            "source=\(source.id) " +
            "tab=\(listTab?.id ?? "default") " +
            "title=\(listTab?.title ?? "default") " +
            "url=\(url.absoluteString)"
        )
        #endif

        let html: String = try await self.httpClient.getString(from: url)
        let items: [ContentItem] = try self.ruleParser.parseList(html: html, source: source, listRule: listRule)

        try self.contentRepository.saveItems(items)
        return items
    }
}
