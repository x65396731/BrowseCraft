import BrowseCraftCore

// 中文注释：P3-5.1 只建立 App 规则模型到 Core 轻量 primitive 的映射，不迁移 SiteRule 大模型。
extension RuleDebugStage {
    var sourceRuntimeOperation: SourceRuntimeOperation {
        switch self {
        case .list:
            return .list
        case .search:
            return .search
        case .detail:
            return .detail
        case .reader:
            return .reader
        }
    }
}

extension SourceRuntimeOperation {
    var ruleDebugStage: RuleDebugStage? {
        switch self {
        case .list:
            return .list
        case .search:
            return .search
        case .detail:
            return .detail
        case .reader:
            return .reader
        case .debug:
            return nil
        }
    }
}

extension RuleDebugField {
    var sourceRuleField: SourceRuleField {
        switch self {
        case .item:
            return .item
        case .title:
            return .title
        case .link:
            return .link
        case .cover:
            return .cover
        case .latestText:
            return .latestText
        case .chapter:
            return .chapter
        case .image:
            return .image
        case .unknown:
            return .unknown
        }
    }
}

extension RuleCandidateField {
    var sourceRuleField: SourceRuleField {
        switch self {
        case .section:
            return .section
        case .item:
            return .item
        case .title:
            return .title
        case .link:
            return .link
        case .cover:
            return .cover
        case .latestText:
            return .latestText
        case .chapterContainer:
            return .chapterContainer
        case .chapterItem:
            return .chapterItem
        case .chapterTitle:
            return .chapterTitle
        case .chapterLink:
            return .chapterLink
        case .image:
            return .image
        case .nextPage:
            return .nextPage
        case .unknown:
            return .unknown
        }
    }
}

extension SelectorKind {
    var sourceRuleSelectorKind: SourceRuleSelectorKind {
        switch self {
        case .css:
            return .css
        case .jsonPath:
            return .jsonPath
        case .xpath:
            return .xpath
        case .current:
            return .current
        }
    }
}

extension SourceRuleSelectorKind {
    var selectorKind: SelectorKind {
        switch self {
        case .css:
            return .css
        case .jsonPath:
            return .jsonPath
        case .xpath:
            return .xpath
        case .current:
            return .current
        }
    }
}

extension ExtractFunction {
    var sourceRuleExtractFunction: SourceRuleExtractFunction {
        switch self {
        case .text:
            return .text
        case .html:
            return .html
        case .attr:
            return .attr
        case .raw:
            return .raw
        case .url:
            return .url
        case .decodeBase64:
            return .decodeBase64
        case .removingPercentEncoding:
            return .removingPercentEncoding
        case .addingPercentEncoding:
            return .addingPercentEncoding
        case .replace:
            return .replace
        case .decompressFromBase64:
            return .decompressFromBase64
        case .reversed:
            return .reversed
        case .regexReplacement:
            return .regexReplacement
        }
    }
}

extension SourceRuleExtractFunction {
    var extractFunction: ExtractFunction {
        switch self {
        case .text:
            return .text
        case .html:
            return .html
        case .attr:
            return .attr
        case .raw:
            return .raw
        case .url:
            return .url
        case .decodeBase64:
            return .decodeBase64
        case .removingPercentEncoding:
            return .removingPercentEncoding
        case .addingPercentEncoding:
            return .addingPercentEncoding
        case .replace:
            return .replace
        case .decompressFromBase64:
            return .decompressFromBase64
        case .reversed:
            return .reversed
        case .regexReplacement:
            return .regexReplacement
        }
    }
}

extension RuleDebugSessionStatus {
    var sourceDebugStatus: SourceDebugStatus {
        switch self {
        case .running:
            return .running
        case .succeeded:
            return .succeeded
        case .empty:
            return .empty
        case .failed:
            return .failed
        }
    }
}

extension RuleDebugInput {
    var sourceDebugInputSummary: SourceDebugInputSummary {
        SourceDebugInputSummary(
            sourceID: self.sourceID,
            sourceName: self.sourceName,
            operation: self.stage.sourceRuntimeOperation,
            pageID: self.pageID,
            tabID: self.tabID,
            ruleID: self.ruleID,
            keyword: self.keyword,
            page: self.page,
            url: self.url
        )
    }
}

extension RuleDebugRequestSummary {
    var sourceDebugRequestSummary: SourceDebugRequestSummary {
        SourceDebugRequestSummary(
            needsWebView: self.needsWebView,
            autoScroll: self.autoScroll,
            scope: self.scope,
            mergePolicy: self.mergePolicy,
            cookiePolicy: self.cookiePolicy,
            charset: self.charset,
            headerCount: self.headerCount,
            hasBody: self.hasBody
        )
    }
}

extension RuleDebugResponseSummary {
    var sourceDebugResponseSummary: SourceDebugResponseSummary {
        SourceDebugResponseSummary(
            statusCode: self.statusCode,
            contentLength: self.contentLength,
            finalURL: self.finalURL
        )
    }
}

extension RuleDebugRequestLog {
    var sourceDebugRequestLog: SourceDebugRequestLog {
        SourceDebugRequestLog(
            id: self.id,
            operation: self.stage.sourceRuntimeOperation,
            url: self.url,
            method: self.method,
            requestSummary: self.requestSummary.sourceDebugRequestSummary,
            startedAt: self.startedAt,
            completedAt: self.completedAt,
            responseSummary: self.responseSummary?.sourceDebugResponseSummary,
            errorMessage: self.errorMessage
        )
    }
}

extension RuleDebugExtractionLog {
    var sourceDebugExtractionLog: SourceDebugExtractionLog {
        SourceDebugExtractionLog(
            id: self.id,
            operation: self.stage.sourceRuntimeOperation,
            ruleID: self.ruleID,
            selector: self.selector,
            field: self.field?.sourceRuleField,
            candidateCount: self.candidateCount,
            outputCount: self.outputCount,
            samples: self.samples,
            message: self.message
        )
    }
}

extension RuleDebugIssueSeverity {
    var sourceRuntimeIssueSeverity: SourceRuntimeIssueSeverity {
        switch self {
        case .info:
            return .info
        case .warning:
            return .warning
        case .error:
            return .error
        }
    }
}

extension RuleDebugIssueCategory {
    var sourceDebugIssueCategory: SourceDebugIssueCategory {
        switch self {
        case .requestFailed:
            return .requestFailed
        case .selectorEmpty:
            return .selectorEmpty
        case .fieldMissing:
            return .fieldMissing
        case .invalidURL:
            return .invalidURL
        case .ruleConfiguration:
            return .ruleConfiguration
        case .parserError:
            return .parserError
        case .unknown:
            return .unknown
        }
    }
}

extension RuleDebugIssue {
    var sourceDebugIssue: SourceDebugIssue {
        SourceDebugIssue(
            id: self.id,
            severity: self.severity.sourceRuntimeIssueSeverity,
            category: self.category.sourceDebugIssueCategory,
            operation: self.stage.sourceRuntimeOperation,
            ruleID: self.ruleID,
            field: self.field?.sourceRuleField,
            message: self.message
        )
    }
}

extension RuleDebugPreviewItem {
    var sourceDebugPreviewItem: SourceDebugPreviewItem {
        SourceDebugPreviewItem(
            id: self.id,
            title: self.title,
            detailURL: self.detailURL,
            chapterURL: self.chapterURL,
            coverURL: self.coverURL,
            imageURL: self.imageURL,
            latestText: self.latestText,
            sourceIndex: self.sourceIndex,
            issues: self.issues.map { issue in issue.sourceDebugIssue }
        )
    }
}

extension RuleDebugSession {
    var sourceDebugSnapshot: SourceDebugSnapshot {
        SourceDebugSnapshot(
            id: self.id,
            startedAt: self.startedAt,
            completedAt: self.completedAt,
            input: self.input.sourceDebugInputSummary,
            requestLogs: self.requestLogs.map { log in log.sourceDebugRequestLog },
            extractionLogs: self.extractionLogs.map { log in log.sourceDebugExtractionLog },
            previewItems: self.previewItems.map { item in item.sourceDebugPreviewItem },
            issues: self.issues.map { issue in issue.sourceDebugIssue },
            status: self.status.sourceDebugStatus
        )
    }
}
