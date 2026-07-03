import Foundation

// 中文注释：RuleDebugUseCases 承载 P2-3 RuleDebugger 的只读调试流程，不写缓存、不修改 Source。

/// 中文注释：列表调试用例复用正式请求和解析链路，但只返回 Debug Session。
struct ListDebugUseCase {
    private let pageContentLoader: PageContentLoader
    private let ruleParser: RuleParsingService
    private let paginationParser: RulePaginationParsingService?
    private let candidateAnalyzer: RuleCandidateAnalyzingService?
    private let urlResolver: URLResolvingService
    private let now: () -> Date
    private let idGenerator: () -> String

    init(
        pageContentLoader: PageContentLoader,
        ruleParser: RuleParsingService,
        urlResolver: URLResolvingService,
        candidateAnalyzer: RuleCandidateAnalyzingService? = nil,
        now: @escaping () -> Date = Date.init,
        idGenerator: @escaping () -> String = {
            return UUID().uuidString
        }
    ) {
        self.pageContentLoader = pageContentLoader
        self.ruleParser = ruleParser
        self.paginationParser = ruleParser as? RulePaginationParsingService
        self.candidateAnalyzer = candidateAnalyzer
        self.urlResolver = urlResolver
        self.now = now
        self.idGenerator = idGenerator
    }

    /// 中文注释：兼容测试和旧装配入口；HTTPClient 本身也是 PageContentLoader。
    init(
        httpClient: HTTPClient,
        ruleParser: RuleParsingService,
        urlResolver: URLResolvingService,
        candidateAnalyzer: RuleCandidateAnalyzingService? = nil,
        now: @escaping () -> Date = Date.init,
        idGenerator: @escaping () -> String = {
            return UUID().uuidString
        }
    ) {
        self.init(
            pageContentLoader: httpClient,
            ruleParser: ruleParser,
            urlResolver: urlResolver,
            candidateAnalyzer: candidateAnalyzer,
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
            candidateReport: nil,
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
            self.attachListCandidates(
                html: html,
                source: source,
                listRule: listRule,
                listTab: listTab,
                currentURL: url,
                session: &session
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

    private func attachListCandidates(
        html: String,
        source: Source,
        listRule: ListRule,
        listTab: ListTabRule?,
        currentURL: URL,
        session: inout RuleDebugSession
    ) {
        guard let candidateAnalyzer: RuleCandidateAnalyzingService = self.candidateAnalyzer else {
            return
        }

        do {
            let listReport: RuleCandidateReport = try candidateAnalyzer.analyzeList(
                html: html,
                source: source,
                listRule: listRule,
                pageID: session.input.pageID,
                url: currentURL.absoluteString
            )
            let paginationReport: RuleCandidateReport = try candidateAnalyzer.analyzePagination(
                html: html,
                source: source,
                pagination: listRule.pagination,
                stage: .list,
                pageID: session.input.pageID,
                ruleID: listRule.id,
                currentURL: currentURL.absoluteString,
                urlTemplate: listTab?.list.url ?? listRule.url
            )
            session.candidateReport = mergedCandidateReport(
                primary: listReport,
                secondary: paginationReport
            )
        } catch {
            session.issues.append(
                self.issue(
                    severity: .warning,
                    category: .unknown,
                    ruleID: listRule.id,
                    field: nil,
                    message: "Candidate recommendations failed: \(error.localizedDescription)"
                )
            )
        }
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
                chapterURL: nil,
                coverURL: item.coverURL,
                imageURL: nil,
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
    private let candidateAnalyzer: RuleCandidateAnalyzingService?
    private let urlResolver: URLResolvingService
    private let now: () -> Date
    private let idGenerator: () -> String

    init(
        pageContentLoader: PageContentLoader,
        ruleParser: RuleParsingService,
        urlResolver: URLResolvingService,
        candidateAnalyzer: RuleCandidateAnalyzingService? = nil,
        now: @escaping () -> Date = Date.init,
        idGenerator: @escaping () -> String = {
            return UUID().uuidString
        }
    ) {
        self.pageContentLoader = pageContentLoader
        self.ruleParser = ruleParser
        self.paginationParser = ruleParser as? RulePaginationParsingService
        self.candidateAnalyzer = candidateAnalyzer
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
            candidateReport: nil,
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
            self.attachSearchCandidates(
                html: html,
                source: source,
                entry: entry,
                currentURL: url,
                urlOverride: urlOverride,
                session: &session
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

    private func attachSearchCandidates(
        html: String,
        source: Source,
        entry: SearchDebugRuleEntry,
        currentURL: URL,
        urlOverride: String?,
        session: inout RuleDebugSession
    ) {
        guard let candidateAnalyzer: RuleCandidateAnalyzingService = self.candidateAnalyzer else {
            return
        }

        do {
            let listRule: ListRule? = entry.rule.listRuleRef.flatMap { listRuleID in
                return source.rule.ruleSets?.listRule(id: listRuleID)
            }
            let listReport: RuleCandidateReport = try candidateAnalyzer.analyzeList(
                html: html,
                source: source,
                listRule: listRule,
                pageID: session.input.pageID,
                url: currentURL.absoluteString
            )
            let paginationReport: RuleCandidateReport = try candidateAnalyzer.analyzePagination(
                html: html,
                source: source,
                pagination: entry.rule.pagination,
                stage: .search,
                pageID: session.input.pageID,
                ruleID: entry.rule.id,
                currentURL: currentURL.absoluteString,
                urlTemplate: self.searchURLTemplate(
                    source: source,
                    searchRule: entry.rule,
                    urlOverride: urlOverride
                )
            )
            session.candidateReport = mergedCandidateReport(
                primary: listReport,
                secondary: paginationReport
            )
        } catch {
            session.issues.append(
                self.issue(
                    severity: .warning,
                    category: .unknown,
                    ruleID: entry.rule.id,
                    field: nil,
                    message: "Candidate recommendations failed: \(error.localizedDescription)"
                )
            )
        }
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

    private func searchURLTemplate(
        source: Source,
        searchRule: SearchRule,
        urlOverride: String?
    ) -> String {
        if let urlOverride: String = self.nonEmpty(urlOverride) {
            return urlOverride
        }

        if let searchTemplate: URLTemplateRule = source.rule.urlPatterns?.searchTemplate {
            return searchTemplate.template
        }

        return searchRule.url
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
                chapterURL: nil,
                coverURL: item.coverURL,
                imageURL: nil,
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

/// 中文注释：详情调试用例只读取详情页并解析章节预览，不写缓存、不刷新书库、不修改 Source。
struct DetailDebugUseCase {
    private let pageContentLoader: PageContentLoader
    private let ruleParser: RuleParsingService
    private let candidateAnalyzer: RuleCandidateAnalyzingService?
    private let urlResolver: URLResolvingService
    private let now: () -> Date
    private let idGenerator: () -> String

    init(
        pageContentLoader: PageContentLoader,
        ruleParser: RuleParsingService,
        urlResolver: URLResolvingService,
        candidateAnalyzer: RuleCandidateAnalyzingService? = nil,
        now: @escaping () -> Date = Date.init,
        idGenerator: @escaping () -> String = {
            return UUID().uuidString
        }
    ) {
        self.pageContentLoader = pageContentLoader
        self.ruleParser = ruleParser
        self.candidateAnalyzer = candidateAnalyzer
        self.urlResolver = urlResolver
        self.now = now
        self.idGenerator = idGenerator
    }

    func execute(
        source: Source,
        detailURL: String,
        context: ListContext? = nil
    ) async -> RuleDebugSession {
        let startedAt: Date = self.now()
        let resolvedRule: ResolvedSiteRule = RuleResolver().resolve(source.rule)
        let detailContext: ResolvedDetailContext? = resolvedRule.primaryDetailContext
        let detailRule: DetailRule? = detailContext.flatMap { context in
            return resolvedRule.detailRule(for: context)
        }
        let input: RuleDebugInput = RuleDebugInput(
            sourceID: source.id,
            sourceName: source.name,
            stage: .detail,
            pageID: detailContext?.pageID,
            tabID: context?.tabId,
            ruleID: detailContext?.ruleID,
            keyword: nil,
            page: nil,
            url: detailURL,
            context: context
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
            candidateReport: nil,
            issues: []
        )

        guard let detailContext: ResolvedDetailContext = detailContext,
              let detailRule: DetailRule = detailRule else {
            session.issues.append(
                self.issue(
                    severity: .error,
                    category: .ruleConfiguration,
                    ruleID: nil,
                    field: .chapter,
                    message: "Missing detail rule."
                )
            )
            session.completedAt = self.now()
            return session
        }

        let url: URL
        do {
            url = try self.debugURL(source: source, detailURL: detailURL)
        } catch {
            session.issues.append(
                self.issue(
                    severity: .error,
                    category: .invalidURL,
                    ruleID: detailContext.ruleID,
                    field: nil,
                    message: error.localizedDescription
                )
            )
            session.completedAt = self.now()
            return session
        }

        let request: RequestConfig? = detailContext.request
        let requestStartedAt: Date = self.now()
        var requestLog: RuleDebugRequestLog = RuleDebugRequestLog(
            id: self.idGenerator(),
            stage: .detail,
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

            let chapters: [ChapterLink] = try self.ruleParser.parseDetailChapters(
                html: html,
                source: source,
                detailRule: detailRule,
                pageURL: url.absoluteString,
                context: context
            )
            session.previewItems = self.previewItems(from: chapters)
            session.extractionLogs.append(
                RuleDebugExtractionLog(
                    id: self.idGenerator(),
                    stage: .detail,
                    ruleID: detailContext.ruleID,
                    selector: self.chapterSelector(detailRule),
                    field: .chapter,
                    candidateCount: nil,
                    outputCount: chapters.count,
                    samples: Array(chapters.prefix(3).map(\.title)),
                    message: "Parsed chapter preview items."
                )
            )
            self.attachDetailCandidates(
                html: html,
                source: source,
                detailRule: detailRule,
                currentURL: url,
                session: &session
            )

            if chapters.isEmpty {
                session.issues.append(
                    self.issue(
                        severity: .warning,
                        category: .selectorEmpty,
                        ruleID: detailContext.ruleID,
                        field: .chapter,
                        message: "Detail rule produced no chapter preview items."
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
                    ruleID: detailContext.ruleID,
                    field: .chapter,
                    message: classifiedError.localizedDescription
                )
            )
        }

        session.completedAt = self.now()
        return session
    }

    private func attachDetailCandidates(
        html: String,
        source: Source,
        detailRule: DetailRule,
        currentURL: URL,
        session: inout RuleDebugSession
    ) {
        guard let candidateAnalyzer: RuleCandidateAnalyzingService = self.candidateAnalyzer else {
            return
        }

        do {
            session.candidateReport = try candidateAnalyzer.analyzeDetail(
                html: html,
                source: source,
                detailRule: detailRule,
                pageID: session.input.pageID,
                url: currentURL.absoluteString
            )
        } catch {
            session.issues.append(
                self.issue(
                    severity: .warning,
                    category: .unknown,
                    ruleID: detailRule.id,
                    field: nil,
                    message: "Candidate recommendations failed: \(error.localizedDescription)"
                )
            )
        }
    }

    private func debugURL(source: Source, detailURL: String) throws -> URL {
        let absoluteURLString: String = self.urlResolver.absoluteString(
            detailURL,
            baseURLString: source.baseURL
        )

        guard let url: URL = URL(string: absoluteURLString),
              url.scheme != nil else {
            throw URLResolvingError.invalidURL(detailURL)
        }

        return url
    }

    private func previewItems(from chapters: [ChapterLink]) -> [RuleDebugPreviewItem] {
        return chapters.enumerated().map { index, chapter in
            return RuleDebugPreviewItem(
                id: "\(chapter.url)#\(index)",
                title: chapter.title,
                detailURL: nil,
                chapterURL: chapter.url,
                coverURL: nil,
                imageURL: nil,
                latestText: nil,
                sourceIndex: index,
                issues: []
            )
        }
    }

    private func chapterSelector(_ detailRule: DetailRule) -> String? {
        if let selector: String = detailRule.chapterRule?.item.selector {
            return selector
        }

        return detailRule.chapterItem
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
            stage: .detail,
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
}

/// 中文注释：阅读调试用例只读取章节页并解析图片预览，不写缓存、不刷新书库、不修改 Source。
struct ReaderDebugUseCase {
    private let pageContentLoader: PageContentLoader
    private let ruleParser: RuleParsingService
    private let candidateAnalyzer: RuleCandidateAnalyzingService?
    private let urlResolver: URLResolvingService
    private let now: () -> Date
    private let idGenerator: () -> String

    init(
        pageContentLoader: PageContentLoader,
        ruleParser: RuleParsingService,
        urlResolver: URLResolvingService,
        candidateAnalyzer: RuleCandidateAnalyzingService? = nil,
        now: @escaping () -> Date = Date.init,
        idGenerator: @escaping () -> String = {
            return UUID().uuidString
        }
    ) {
        self.pageContentLoader = pageContentLoader
        self.ruleParser = ruleParser
        self.candidateAnalyzer = candidateAnalyzer
        self.urlResolver = urlResolver
        self.now = now
        self.idGenerator = idGenerator
    }

    func execute(
        source: Source,
        chapterURL: String,
        context: ListContext? = nil
    ) async -> RuleDebugSession {
        let startedAt: Date = self.now()
        let resolvedRule: ResolvedSiteRule = RuleResolver().resolve(source.rule)
        let readerContext: ResolvedReaderContext? = resolvedRule.primaryReaderContext
        let galleryRule: GalleryRule? = readerContext.flatMap { context in
            return resolvedRule.galleryRule(for: context)
        }
        let input: RuleDebugInput = RuleDebugInput(
            sourceID: source.id,
            sourceName: source.name,
            stage: .reader,
            pageID: readerContext?.pageID,
            tabID: context?.tabId,
            ruleID: readerContext?.ruleID,
            keyword: nil,
            page: nil,
            url: chapterURL,
            context: context
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
            candidateReport: nil,
            issues: []
        )

        guard let readerContext: ResolvedReaderContext = readerContext,
              let galleryRule: GalleryRule = galleryRule else {
            session.issues.append(
                self.issue(
                    severity: .error,
                    category: .ruleConfiguration,
                    ruleID: nil,
                    field: .image,
                    message: "Missing reader rule."
                )
            )
            session.completedAt = self.now()
            return session
        }

        let url: URL
        do {
            url = try self.debugURL(source: source, chapterURL: chapterURL)
        } catch {
            session.issues.append(
                self.issue(
                    severity: .error,
                    category: .invalidURL,
                    ruleID: readerContext.ruleID,
                    field: nil,
                    message: error.localizedDescription
                )
            )
            session.completedAt = self.now()
            return session
        }

        let request: RequestConfig? = readerContext.request
        let requestStartedAt: Date = self.now()
        var requestLog: RuleDebugRequestLog = RuleDebugRequestLog(
            id: self.idGenerator(),
            stage: .reader,
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

            let chapter: ReaderChapter = try self.ruleParser.parseReader(
                html: html,
                source: source,
                galleryRule: galleryRule,
                pageURL: url.absoluteString,
                context: context
            )
            session.previewItems = self.previewItems(from: chapter.pageImageURLs)
            session.extractionLogs.append(
                RuleDebugExtractionLog(
                    id: self.idGenerator(),
                    stage: .reader,
                    ruleID: readerContext.ruleID,
                    selector: self.imageSelector(galleryRule),
                    field: .image,
                    candidateCount: nil,
                    outputCount: chapter.pageImageURLs.count,
                    samples: Array(chapter.pageImageURLs.prefix(3)),
                    message: "Parsed reader image preview items."
                )
            )
            self.attachReaderCandidates(
                html: html,
                source: source,
                galleryRule: galleryRule,
                currentURL: url,
                session: &session
            )

            if chapter.pageImageURLs.isEmpty {
                session.issues.append(
                    self.issue(
                        severity: .warning,
                        category: .selectorEmpty,
                        ruleID: readerContext.ruleID,
                        field: .image,
                        message: "Reader rule produced no image preview items."
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
                    ruleID: readerContext.ruleID,
                    field: .image,
                    message: classifiedError.localizedDescription
                )
            )
        }

        session.completedAt = self.now()
        return session
    }

    private func attachReaderCandidates(
        html: String,
        source: Source,
        galleryRule: GalleryRule,
        currentURL: URL,
        session: inout RuleDebugSession
    ) {
        guard let candidateAnalyzer: RuleCandidateAnalyzingService = self.candidateAnalyzer else {
            return
        }

        do {
            session.candidateReport = try candidateAnalyzer.analyzeReader(
                html: html,
                source: source,
                galleryRule: galleryRule,
                pageID: session.input.pageID,
                url: currentURL.absoluteString
            )
        } catch {
            session.issues.append(
                self.issue(
                    severity: .warning,
                    category: .unknown,
                    ruleID: galleryRule.id,
                    field: nil,
                    message: "Candidate recommendations failed: \(error.localizedDescription)"
                )
            )
        }
    }

    private func debugURL(source: Source, chapterURL: String) throws -> URL {
        let absoluteURLString: String = self.urlResolver.absoluteString(
            chapterURL,
            baseURLString: source.baseURL
        )

        guard let url: URL = URL(string: absoluteURLString),
              url.scheme != nil else {
            throw URLResolvingError.invalidURL(chapterURL)
        }

        return url
    }

    private func previewItems(from imageURLs: [String]) -> [RuleDebugPreviewItem] {
        return imageURLs.enumerated().map { index, imageURL in
            return RuleDebugPreviewItem(
                id: "\(imageURL)#\(index)",
                title: "Image \(index + 1)",
                detailURL: nil,
                chapterURL: nil,
                coverURL: nil,
                imageURL: imageURL,
                latestText: nil,
                sourceIndex: index,
                issues: []
            )
        }
    }

    private func imageSelector(_ galleryRule: GalleryRule) -> String? {
        if let selector: String = galleryRule.item?.selector {
            return selector
        }

        return galleryRule.imageItem
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
            stage: .reader,
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
}

private func mergedCandidateReport(
    primary: RuleCandidateReport,
    secondary: RuleCandidateReport
) -> RuleCandidateReport {
    let candidates: [RuleCandidate] = primary.candidates + secondary.candidates
    return RuleCandidateReport(
        id: primary.id,
        sourceID: primary.sourceID,
        sourceName: primary.sourceName,
        stage: primary.stage,
        pageID: primary.pageID,
        ruleID: primary.ruleID,
        url: primary.url,
        generatedAt: primary.generatedAt,
        candidates: candidates,
        summary: RuleCandidateSummary(
            candidateCount: candidates.count,
            highConfidenceCount: candidates.filter { candidate in
                return candidate.score.confidence == .high
            }.count,
            warningCount: candidates.reduce(0) { count, candidate in
                return count + candidate.warnings.count
            },
            coveredFields: Array(Set(candidates.map(\.field))).sorted { lhs, rhs in
                return lhs.rawValue < rhs.rawValue
            }
        )
    )
}
