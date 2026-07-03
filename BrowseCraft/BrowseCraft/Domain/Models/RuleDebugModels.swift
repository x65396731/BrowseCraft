import Foundation

// 中文注释：RuleDebugModels 是 P2-3 RuleDebugger 的数据合同；它只描述调试结果，不执行网络或解析。

/// 中文注释：一次规则调试会话的完整快照，供 UseCase、ViewModel 和 UI 共同读取。
struct RuleDebugSession: Identifiable, Hashable {
    var id: String
    var startedAt: Date
    var completedAt: Date?
    var input: RuleDebugInput
    var requestLogs: [RuleDebugRequestLog]
    var extractionLogs: [RuleDebugExtractionLog]
    var previewItems: [RuleDebugPreviewItem]
    var pagination: PaginationResolution?
    var candidateReport: RuleCandidateReport?
    var issues: [RuleDebugIssue]

    var status: RuleDebugSessionStatus {
        if self.issues.contains(where: { issue in issue.severity == .error }) {
            return .failed
        }

        if self.completedAt == nil {
            return .running
        }

        if self.previewItems.isEmpty {
            return .empty
        }

        return .succeeded
    }
}

enum RuleDebugSessionStatus: String, Hashable {
    case running
    case succeeded
    case empty
    case failed
}

/// 中文注释：调试输入描述用户想检查哪个 Source、哪个规则入口和哪个 URL。
struct RuleDebugInput: Hashable {
    var sourceID: String
    var sourceName: String
    var stage: RuleDebugStage
    var pageID: String?
    var tabID: String?
    var ruleID: String?
    var keyword: String?
    var page: Int?
    var url: String?
    var context: ListContext?
}

enum RuleDebugStage: String, Hashable {
    case list
    case search
    case detail
    case reader
}

struct RuleListDebugParseResult: Hashable {
    var items: [ContentItem]
    var extractionLogs: [RuleDebugExtractionLog]
    var issues: [RuleDebugIssue]
}

protocol RuleListDebugParsingService {
    func debugParseList(
        html: String,
        source: Source,
        listRule: ListRule,
        context: ListContext?,
        sections: [SectionRule]?
    ) throws -> RuleListDebugParseResult
}

/// 中文注释：请求日志只保存可展示的请求摘要，不保存 Cookie、完整 HTML 或大体积正文。
struct RuleDebugRequestLog: Identifiable, Hashable {
    var id: String
    var stage: RuleDebugStage
    var url: String
    var method: String
    var requestSummary: RuleDebugRequestSummary
    var startedAt: Date
    var completedAt: Date?
    var responseSummary: RuleDebugResponseSummary?
    var errorMessage: String?
}

struct RuleDebugRequestSummary: Hashable {
    var needsWebView: Bool
    var autoScroll: Bool
    var scope: String?
    var mergePolicy: String?
    var cookiePolicy: String?
    var charset: String?
    var headerCount: Int
    var hasBody: Bool
}

extension RuleDebugRequestSummary {
    init(request: RequestConfig?) {
        self.needsWebView = request?.needsWebView ?? false
        self.autoScroll = request?.autoScroll ?? false
        self.scope = request?.scope?.rawValue
        self.mergePolicy = request?.mergePolicy?.rawValue
        self.cookiePolicy = request?.cookiePolicy?.rawValue
        self.charset = request?.charset?.rawValue
        self.headerCount = request?.headers?.count ?? 0
        self.hasBody = request?.body != nil
    }
}

struct RuleDebugResponseSummary: Hashable {
    var statusCode: Int?
    var contentLength: Int?
    var finalURL: String?
}

/// 中文注释：解析日志描述某个 selector 或字段提取阶段的候选数和结果数量。
struct RuleDebugExtractionLog: Identifiable, Hashable {
    var id: String
    var stage: RuleDebugStage
    var ruleID: String?
    var selector: String?
    var field: RuleDebugField?
    var candidateCount: Int?
    var outputCount: Int?
    var samples: [String]
    var message: String?
}

enum RuleDebugField: String, Hashable {
    case item
    case title
    case link
    case cover
    case latestText
    case chapter
    case image
    case unknown
}

/// 中文注释：预览项是 Debugger 展示用的轻量解析结果，避免 UI 直接依赖完整缓存模型。
struct RuleDebugPreviewItem: Identifiable, Hashable {
    var id: String
    var title: String
    var detailURL: String?
    var coverURL: String?
    var latestText: String?
    var sourceIndex: Int
    var issues: [RuleDebugIssue]
}

/// 中文注释：Issue 用稳定类别表达问题，UI 可直接按 severity 分组展示。
struct RuleDebugIssue: Identifiable, Hashable {
    var id: String
    var severity: RuleDebugIssueSeverity
    var category: RuleDebugIssueCategory
    var stage: RuleDebugStage
    var ruleID: String?
    var field: RuleDebugField?
    var message: String
}

enum RuleDebugIssueSeverity: String, Hashable {
    case info
    case warning
    case error
}

enum RuleDebugIssueCategory: String, Hashable {
    case requestFailed
    case selectorEmpty
    case fieldMissing
    case invalidURL
    case ruleConfiguration
    case parserError
    case unknown
}
