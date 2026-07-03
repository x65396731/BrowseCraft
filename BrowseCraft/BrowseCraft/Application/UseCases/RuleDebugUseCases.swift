import Foundation

// 中文注释：RuleDebugUseCases 承载 P2-3 RuleDebugger 的只读调试流程，不写缓存、不修改 Source。

/// 中文注释：列表调试用例复用正式请求和解析链路，但只返回 Debug Session。
struct ListDebugUseCase {
    private let pageContentLoader: PageContentLoader
    private let ruleParser: RuleParsingService
    private let paginationParser: RulePaginationParsingService?
    private let urlResolver: URLResolvingService
    private let now: () -> Date
    private let idGenerator: () -> String

    init(
        pageContentLoader: PageContentLoader,
        ruleParser: RuleParsingService,
        urlResolver: URLResolvingService,
        now: @escaping () -> Date = Date.init,
        idGenerator: @escaping () -> String = {
            return UUID().uuidString
        }
    ) {
        self.pageContentLoader = pageContentLoader
        self.ruleParser = ruleParser
        self.paginationParser = ruleParser as? RulePaginationParsingService
        self.urlResolver = urlResolver
        self.now = now
        self.idGenerator = idGenerator
    }

    /// 中文注释：兼容测试和旧装配入口；HTTPClient 本身也是 PageContentLoader。
    init(
        httpClient: HTTPClient,
        ruleParser: RuleParsingService,
        urlResolver: URLResolvingService,
        now: @escaping () -> Date = Date.init,
        idGenerator: @escaping () -> String = {
            return UUID().uuidString
        }
    ) {
        self.init(
            pageContentLoader: httpClient,
            ruleParser: ruleParser,
            urlResolver: urlResolver,
            now: now,
            idGenerator: idGenerator
        )
    }

    func execute(
        source: Source,
        listTab: ListTabRule? = nil,
        page: Int = 1,
        urlOverride: String? = nil
    ) async -> RuleDebugSession {
        let listRule: ListRule = listTab?.list ?? source.rule.list
        let request: RequestConfig? = source.rule.request(for: listTab)
        let startedAt: Date = self.now()
        let input: RuleDebugInput = RuleDebugInput(
            sourceID: source.id,
            sourceName: source.name,
            stage: .list,
            pageID: listTab?.context?.pageId ?? listTab?.id,
            tabID: listTab?.id,
            ruleID: listRule.id,
            keyword: nil,
            page: page,
            url: urlOverride,
            context: self.listContext(listTab: listTab, listRule: listRule)
        )
        var session: RuleDebugSession = RuleDebugSession(
            id: self.idGenerator(),
            startedAt: startedAt,
            completedAt: nil,
            input: input,
            requestLogs: [],
            extractionLogs: [],
            previewItems: [],
            pagination: nil,
            issues: []
        )

        let url: URL
        do {
            url = try self.debugURL(
                source: source,
                listRule: listRule,
                page: page,
                urlOverride: urlOverride
            )
        } catch {
            session.issues.append(
                self.issue(
                    severity: .error,
                    category: .invalidURL,
                    ruleID: listRule.id,
                    field: nil,
                    message: error.localizedDescription
                )
            )
            session.completedAt = self.now()
            return session
        }

        let requestStartedAt: Date = self.now()
        var requestLog: RuleDebugRequestLog = RuleDebugRequestLog(
            id: self.idGenerator(),
            stage: .list,
            url: url.absoluteString,
            method: request?.method?.rawValue ?? HTTPMethod.get.rawValue,
            requestSummary: RuleDebugRequestSummary(request: request),
            startedAt: requestStartedAt,
            completedAt: nil,
            responseSummary: nil,
            errorMessage: nil
        )

        do {
            let html: String = try await self.pageContentLoader.getString(from: url, request: request)
            requestLog.completedAt = self.now()
            requestLog.responseSummary = RuleDebugResponseSummary(
                statusCode: nil,
                contentLength: html.count,
                finalURL: url.absoluteString
            )
            session.requestLogs.append(requestLog)

            let items: [ContentItem]

            if let debugParser: RuleListDebugParsingService = self.ruleParser as? RuleListDebugParsingService {
                let result: RuleListDebugParseResult = try debugParser.debugParseList(
                    html: html,
                    source: source,
                    listRule: listRule,
                    context: input.context,
                    sections: listTab?.sections
                )
                items = result.items
                session.extractionLogs.append(contentsOf: result.extractionLogs)
                session.issues.append(contentsOf: result.issues)
            } else {
                items = try self.ruleParser.parseList(
                    html: html,
                    source: source,
                    listRule: listRule,
                    context: input.context,
                    sections: listTab?.sections
                )
                session.extractionLogs.append(
                    RuleDebugExtractionLog(
                        id: self.idGenerator(),
                        stage: .list,
                        ruleID: listRule.id,
                        selector: listRule.item,
                        field: .item,
                        candidateCount: nil,
                        outputCount: items.count,
                        samples: Array(items.prefix(3).map(\.title)),
                        message: "Parsed list preview items."
                    )
                )
            }

            session.previewItems = self.previewItems(from: items)
            session.pagination = try self.pagination(
                html: html,
                source: source,
                listRule: listRule,
                currentPage: page,
                currentURL: url,
                urlOverride: urlOverride
            )

            if items.isEmpty,
               session.issues.contains(where: { issue in
                   issue.category == .selectorEmpty && issue.field == .item
               }) == false {
                session.issues.append(
                    self.issue(
                        severity: .warning,
                        category: .selectorEmpty,
                        ruleID: listRule.id,
                        field: .item,
                        message: "List rule produced no preview items."
                    )
                )
            }
        } catch {
            requestLog.completedAt = requestLog.completedAt ?? self.now()
            requestLog.errorMessage = error.localizedDescription
            if session.requestLogs.contains(where: { log in log.id == requestLog.id }) == false {
                session.requestLogs.append(requestLog)
            }

            let classifiedError: RuleExecutionError = RuleExecutionErrorClassifier.classified(error)
            session.issues.append(
                self.issue(
                    severity: .error,
                    category: self.issueCategory(for: classifiedError),
                    ruleID: listRule.id,
                    field: nil,
                    message: classifiedError.localizedDescription
                )
            )
        }

        session.completedAt = self.now()
        return session
    }

    private func pagination(
        html: String,
        source: Source,
        listRule: ListRule,
        currentPage: Int,
        currentURL: URL,
        urlOverride: String?
    ) throws -> PaginationResolution? {
        guard let pagination: PaginationRule = listRule.pagination else {
            return nil
        }

        let normalizedPage: Int = max(currentPage, 1)
        if let maxPages: Int = pagination.maxPages,
           normalizedPage >= maxPages {
            return PaginationResolution(
                currentPage: normalizedPage,
                nextPage: nil,
                nextURL: nil,
                source: nil
            )
        }

        let placeholderURL: URL? = try self.placeholderNextPageURL(
            source: source,
            listRule: listRule,
            currentPage: normalizedPage,
            pagination: pagination,
            urlOverride: urlOverride
        )
        let extractedURL: String? = try self.paginationParser?.parseNextPageURL(
            html: html,
            source: source,
            pagination: pagination,
            currentURL: currentURL
        )

        if let extractedURL: String = self.nonEmpty(extractedURL) {
            return PaginationResolution(
                currentPage: normalizedPage,
                nextPage: normalizedPage + 1,
                nextURL: self.urlResolver.absoluteString(
                    extractedURL,
                    baseURLString: currentURL.absoluteString
                ),
                source: .nextPageLink
            )
        }

        if let placeholderURL: URL = placeholderURL {
            return PaginationResolution(
                currentPage: normalizedPage,
                nextPage: normalizedPage + 1,
                nextURL: placeholderURL.absoluteString,
                source: .pagePlaceholder
            )
        }

        return PaginationResolution(
            currentPage: normalizedPage,
            nextPage: nil,
            nextURL: nil,
            source: nil
        )
    }

    private func placeholderNextPageURL(
        source: Source,
        listRule: ListRule,
        currentPage: Int,
        pagination: PaginationRule,
        urlOverride: String?
    ) throws -> URL? {
        guard self.canUsePagePlaceholder(
            source: source,
            listRule: listRule,
            pagination: pagination,
            urlOverride: urlOverride
        ) else {
            return nil
        }

        let nextPage: Int = currentPage + 1
        if let maxPages: Int = pagination.maxPages,
           nextPage > maxPages {
            return nil
        }

        return try self.debugURL(
            source: source,
            listRule: listRule,
            page: nextPage,
            urlOverride: urlOverride
        )
    }

    private func canUsePagePlaceholder(
        source: Source,
        listRule: ListRule,
        pagination: PaginationRule,
        urlOverride: String?
    ) -> Bool {
        let template: String

        if let urlOverride: String = self.nonEmpty(urlOverride) {
            template = urlOverride
        } else if let listTemplate: URLTemplateRule = source.rule.urlPatterns?.listTemplate {
            template = listTemplate.template
        } else {
            template = listRule.url
        }

        if let pagePlaceholder: String = self.nonEmpty(pagination.pagePlaceholder) {
            return template.contains(pagePlaceholder)
        }

        return template.contains("{page")
    }

    private func debugURL(
        source: Source,
        listRule: ListRule,
        page: Int,
        urlOverride: String?
    ) throws -> URL {
        guard let urlOverride: String = self.nonEmpty(urlOverride) else {
            return try self.urlResolver.listURL(for: source, listRule: listRule, page: page)
        }

        let absoluteURLString: String = self.urlResolver.absoluteString(
            urlOverride.replacingOccurrences(of: "{page}", with: String(page)),
            baseURLString: source.baseURL
        )

        guard let url: URL = URL(string: absoluteURLString) else {
            throw URLResolvingError.invalidURL(urlOverride)
        }

        return url
    }

    private func listContext(listTab: ListTabRule?, listRule: ListRule) -> ListContext {
        if var context: ListContext = listTab?.context {
            if context.listRuleId == nil {
                context.listRuleId = listRule.id
            }

            return context
        }

        return ListContext(
            pageId: listTab?.id,
            tabId: listTab?.id,
            sectionId: nil,
            listRuleId: listRule.id,
            sectionRole: .main
        )
    }

    private func previewItems(from items: [ContentItem]) -> [RuleDebugPreviewItem] {
        return items.enumerated().map { index, item in
            return RuleDebugPreviewItem(
                id: item.id,
                title: item.title,
                detailURL: item.detailURL,
                coverURL: item.coverURL,
                latestText: item.latestText,
                sourceIndex: index,
                issues: []
            )
        }
    }

    private func issue(
        severity: RuleDebugIssueSeverity,
        category: RuleDebugIssueCategory,
        ruleID: String?,
        field: RuleDebugField?,
        message: String
    ) -> RuleDebugIssue {
        return RuleDebugIssue(
            id: self.idGenerator(),
            severity: severity,
            category: category,
            stage: .list,
            ruleID: ruleID,
            field: field,
            message: message
        )
    }

    private func issueCategory(for error: RuleExecutionError) -> RuleDebugIssueCategory {
        switch error {
        case .network, .antiBot:
            return .requestFailed
        case .selectorEmpty:
            return .selectorEmpty
        case .ruleConfiguration:
            return .ruleConfiguration
        case .unknown:
            return .unknown
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmedValue: String = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmedValue.isEmpty == false else {
            return nil
        }

        return trimmedValue
    }
}

/// 中文注释：搜索调试用例复用正式搜索请求和解析链路，但只返回调试会话，不写入缓存。
struct SearchDebugUseCase {
    private let pageContentLoader: PageContentLoader
    private let ruleParser: RuleParsingService
    private let paginationParser: RulePaginationParsingService?
    private let urlResolver: URLResolvingService
    private let now: () -> Date
    private let idGenerator: () -> String

    init(
        pageContentLoader: PageContentLoader,
        ruleParser: RuleParsingService,
        urlResolver: URLResolvingService,
        now: @escaping () -> Date = Date.init,
        idGenerator: @escaping () -> String = {
            return UUID().uuidString
        }
    ) {
        self.pageContentLoader = pageContentLoader
        self.ruleParser = ruleParser
        self.paginationParser = ruleParser as? RulePaginationParsingService
        self.urlResolver = urlResolver
        self.now = now
        self.idGenerator = idGenerator
    }

    func execute(
        source: Source,
        keyword: String,
        page: Int = 1,
        urlOverride: String? = nil
    ) async -> RuleDebugSession {
        let startedAt: Date = self.now()
        let entry: SearchDebugRuleEntry?
        let entryError: RuleExecutionError?

        do {
            entry = try self.searchRuleEntry(source: source)
            entryError = nil
        } catch let error as RuleExecutionError {
            entry = nil
            entryError = error
        } catch {
            entry = nil
            entryError = RuleExecutionError.unknown(
                underlyingDescription: error.localizedDescription
            )
        }

        let input: RuleDebugInput = RuleDebugInput(
            sourceID: source.id,
            sourceName: source.name,
            stage: .search,
            pageID: entry?.page?.id,
            tabID: nil,
            ruleID: entry?.rule.id,
            keyword: keyword,
            page: page,
            url: urlOverride,
            context: entry.map { entry in
                return self.searchContext(entry: entry)
            }
        )
        var session: RuleDebugSession = RuleDebugSession(
            id: self.idGenerator(),
            startedAt: startedAt,
            completedAt: nil,
            input: input,
            requestLogs: [],
            extractionLogs: [],
            previewItems: [],
            pagination: nil,
            issues: []
        )

        guard let entry: SearchDebugRuleEntry = entry else {
            let error: RuleExecutionError = entryError ?? RuleExecutionError.ruleConfiguration(
                stage: .search,
                sourceID: source.id,
                reason: "Missing search rule."
            )
            session.issues.append(
                self.issue(
                    severity: .error,
                    category: self.issueCategory(for: error),
                    ruleID: nil,
                    field: nil,
                    message: error.localizedDescription
                )
            )
            session.completedAt = self.now()
            return session
        }

        let url: URL
        do {
            url = try self.searchURL(
                source: source,
                searchRule: entry.rule,
                keyword: keyword,
                page: page,
                urlOverride: urlOverride
            )
        } catch {
            session.issues.append(
                self.issue(
                    severity: .error,
                    category: .invalidURL,
                    ruleID: entry.rule.id,
                    field: nil,
                    message: error.localizedDescription
                )
            )
            session.completedAt = self.now()
            return session
        }

        let request: RequestConfig? = entry.effectiveRequest(sharedRequest: source.rule.sharedRequest)
        let requestStartedAt: Date = self.now()
        var requestLog: RuleDebugRequestLog = RuleDebugRequestLog(
            id: self.idGenerator(),
            stage: .search,
            url: url.absoluteString,
            method: request?.method?.rawValue ?? entry.rule.method?.rawValue ?? HTTPMethod.get.rawValue,
            requestSummary: RuleDebugRequestSummary(request: request),
            startedAt: requestStartedAt,
            completedAt: nil,
            responseSummary: nil,
            errorMessage: nil
        )

        do {
            let html: String = try await self.pageContentLoader.getString(from: url, request: request)
            requestLog.completedAt = self.now()
            requestLog.responseSummary = RuleDebugResponseSummary(
                statusCode: nil,
                contentLength: html.count,
                finalURL: url.absoluteString
            )
            session.requestLogs.append(requestLog)

            let items: [ContentItem] = try self.ruleParser.parseSearch(
                html: html,
                source: source,
                searchRule: entry.rule,
                context: input.context
            )
            session.previewItems = self.previewItems(from: items)
            session.extractionLogs.append(
                RuleDebugExtractionLog(
                    id: self.idGenerator(),
                    stage: .search,
                    ruleID: entry.rule.id,
                    selector: entry.rule.item.selector,
                    field: .item,
                    candidateCount: nil,
                    outputCount: items.count,
                    samples: Array(items.prefix(3).map(\.title)),
                    message: "Parsed search preview items."
                )
            )
            session.pagination = try self.pagination(
                html: html,
                source: source,
                searchRule: entry.rule,
                keyword: keyword,
                currentPage: page,
                currentURL: url,
                urlOverride: urlOverride
            )

            if items.isEmpty {
                session.issues.append(
                    self.issue(
                        severity: .warning,
                        category: .selectorEmpty,
                        ruleID: entry.rule.id,
                        field: .item,
                        message: "Search rule produced no preview items."
                    )
                )
            }
        } catch {
            requestLog.completedAt = requestLog.completedAt ?? self.now()
            requestLog.errorMessage = error.localizedDescription
            if session.requestLogs.contains(where: { log in log.id == requestLog.id }) == false {
                session.requestLogs.append(requestLog)
            }

            let classifiedError: RuleExecutionError = RuleExecutionErrorClassifier.classified(error)
            session.issues.append(
                self.issue(
                    severity: .error,
                    category: self.issueCategory(for: classifiedError),
                    ruleID: entry.rule.id,
                    field: nil,
                    message: classifiedError.localizedDescription
                )
            )
        }

        session.completedAt = self.now()
        return session
    }

    private func searchRuleEntry(source: Source) throws -> SearchDebugRuleEntry {
        guard let ruleSets: RuleSets = source.rule.ruleSets,
              let searchRules: [SearchRule] = ruleSets.searchRules,
              searchRules.isEmpty == false else {
            throw RuleExecutionError.ruleConfiguration(
                stage: .search,
                sourceID: source.id,
                reason: "Missing search rule."
            )
        }

        if let page: PageRule = source.rule.pages?.first(where: { page in
            return page.type == .search
        }) {
            guard let rule: SearchRule = ruleSets.searchRule(id: page.ruleRefs?.search) else {
                throw RuleExecutionError.ruleConfiguration(
                    stage: .search,
                    sourceID: source.id,
                    reason: "Missing referenced search rule: \(page.ruleRefs?.search ?? "nil")"
                )
            }

            return SearchDebugRuleEntry(page: page, rule: rule)
        }

        return SearchDebugRuleEntry(page: nil, rule: searchRules[0])
    }

    private func searchContext(entry: SearchDebugRuleEntry) -> ListContext {
        return ListContext(
            pageId: entry.page?.id,
            tabId: nil,
            sectionId: nil,
            listRuleId: entry.rule.listRuleRef,
            sectionRole: nil
        )
    }

    private func searchURL(
        source: Source,
        searchRule: SearchRule,
        keyword: String,
        page: Int,
        urlOverride: String?
    ) throws -> URL {
        guard let urlOverride: String = self.nonEmpty(urlOverride) else {
            return try self.urlResolver.searchURL(
                for: source,
                searchRule: searchRule,
                keyword: keyword,
                page: page
            )
        }

        var overrideSource: Source = source
        overrideSource.rule.urlPatterns?.searchTemplate = nil
        var overrideRule: SearchRule = searchRule
        overrideRule.url = urlOverride

        return try self.urlResolver.searchURL(
            for: overrideSource,
            searchRule: overrideRule,
            keyword: keyword,
            page: page
        )
    }

    private func pagination(
        html: String,
        source: Source,
        searchRule: SearchRule,
        keyword: String,
        currentPage: Int,
        currentURL: URL,
        urlOverride: String?
    ) throws -> PaginationResolution? {
        guard let pagination: PaginationRule = searchRule.pagination else {
            return nil
        }

        let normalizedPage: Int = max(currentPage, 1)
        if let maxPages: Int = pagination.maxPages,
           normalizedPage >= maxPages {
            return PaginationResolution(currentPage: normalizedPage, nextPage: nil, nextURL: nil, source: nil)
        }

        let placeholderURL: URL? = try self.placeholderNextPageURL(
            source: source,
            searchRule: searchRule,
            keyword: keyword,
            currentPage: normalizedPage,
            pagination: pagination,
            urlOverride: urlOverride
        )
        let extractedURL: String? = try self.paginationParser?.parseNextPageURL(
            html: html,
            source: source,
            pagination: pagination,
            currentURL: currentURL
        )

        if let extractedURL: String = self.nonEmpty(extractedURL) {
            return PaginationResolution(
                currentPage: normalizedPage,
                nextPage: normalizedPage + 1,
                nextURL: self.urlResolver.absoluteString(extractedURL, baseURLString: currentURL.absoluteString),
                source: .nextPageLink
            )
        }

        if let placeholderURL: URL = placeholderURL {
            return PaginationResolution(
                currentPage: normalizedPage,
                nextPage: normalizedPage + 1,
                nextURL: placeholderURL.absoluteString,
                source: .pagePlaceholder
            )
        }

        return PaginationResolution(currentPage: normalizedPage, nextPage: nil, nextURL: nil, source: nil)
    }

    private func placeholderNextPageURL(
        source: Source,
        searchRule: SearchRule,
        keyword: String,
        currentPage: Int,
        pagination: PaginationRule,
        urlOverride: String?
    ) throws -> URL? {
        guard self.canUsePagePlaceholder(
            source: source,
            searchRule: searchRule,
            pagination: pagination,
            urlOverride: urlOverride
        ) else {
            return nil
        }

        let nextPage: Int = currentPage + 1
        if let maxPages: Int = pagination.maxPages,
           nextPage > maxPages {
            return nil
        }

        return try self.searchURL(
            source: source,
            searchRule: searchRule,
            keyword: keyword,
            page: nextPage,
            urlOverride: urlOverride
        )
    }

    private func canUsePagePlaceholder(
        source: Source,
        searchRule: SearchRule,
        pagination: PaginationRule,
        urlOverride: String?
    ) -> Bool {
        let template: String

        if let urlOverride: String = self.nonEmpty(urlOverride) {
            template = urlOverride
        } else if let searchTemplate: URLTemplateRule = source.rule.urlPatterns?.searchTemplate {
            template = searchTemplate.template
        } else {
            template = searchRule.url
        }

        if let pagePlaceholder: String = self.nonEmpty(pagination.pagePlaceholder) {
            return template.contains(pagePlaceholder)
        }

        return template.contains("{page")
    }

    private func previewItems(from items: [ContentItem]) -> [RuleDebugPreviewItem] {
        return items.enumerated().map { index, item in
            return RuleDebugPreviewItem(
                id: item.id,
                title: item.title,
                detailURL: item.detailURL,
                coverURL: item.coverURL,
                latestText: item.latestText,
                sourceIndex: index,
                issues: []
            )
        }
    }

    private func issue(
        severity: RuleDebugIssueSeverity,
        category: RuleDebugIssueCategory,
        ruleID: String?,
        field: RuleDebugField?,
        message: String
    ) -> RuleDebugIssue {
        return RuleDebugIssue(
            id: self.idGenerator(),
            severity: severity,
            category: category,
            stage: .search,
            ruleID: ruleID,
            field: field,
            message: message
        )
    }

    private func issueCategory(for error: RuleExecutionError) -> RuleDebugIssueCategory {
        switch error {
        case .network, .antiBot:
            return .requestFailed
        case .selectorEmpty:
            return .selectorEmpty
        case .ruleConfiguration:
            return .ruleConfiguration
        case .unknown:
            return .unknown
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmedValue: String = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmedValue.isEmpty == false else {
            return nil
        }

        return trimmedValue
    }
}

private struct SearchDebugRuleEntry {
    var page: PageRule?
    var rule: SearchRule

    func effectiveRequest(sharedRequest: RequestConfig?) -> RequestConfig? {
        return self.rule.request ?? self.page?.request ?? sharedRequest
    }
}
