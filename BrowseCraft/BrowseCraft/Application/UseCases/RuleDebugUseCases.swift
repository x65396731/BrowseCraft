import Foundation

// 中文注释：RuleDebugUseCases 承载 P2-3 RuleDebugger 的只读调试流程，不写缓存、不修改 Source。

/// 中文注释：列表调试用例复用正式请求和解析链路，但只返回 Debug Session。
struct ListDebugUseCase {
    private let pageContentLoader: PageContentLoader
    private let ruleParser: RuleParsingService
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
