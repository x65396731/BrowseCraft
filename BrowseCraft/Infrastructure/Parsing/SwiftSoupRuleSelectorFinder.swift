import Foundation
import BrowseCraftCore

/// 中文注释：保留 App 的候选分析端口，确定性 DOM 分析、评分和去重全部委托给 Core。
final class CoreRuleCandidateAnalyzer: RuleCandidateAnalyzingService {
    private let analyzer: BrowseCraftCore.DefaultSourceDiscoveryAnalyzer

    init(
        now: @escaping () -> Date = Date.init,
        idGenerator: @escaping () -> String = {
            return UUID().uuidString
        }
    ) {
        self.analyzer = BrowseCraftCore.DefaultSourceDiscoveryAnalyzer(
            now: now,
            idGenerator: idGenerator
        )
    }

    func analyzeList(
        html: String,
        source: Source,
        listRule: ListRule?,
        pageID: String?,
        url: String?
    ) throws -> RuleCandidateReport {
        let fallbackRuleID: String? = ComicSiteRuleV2Validator()
            .validate(rule: source.rule)
            .resolvedRule?
            .primaryListEntry?
            .ruleID
        return try self.report(
            html: html,
            source: source,
            operation: .list,
            pageID: pageID,
            ruleID: listRule?.id ?? fallbackRuleID,
            url: url,
            candidateScope: .content
        )
    }

    func analyzeDetail(
        html: String,
        source: Source,
        detailRule: DetailRule?,
        pageID: String?,
        url: String?
    ) throws -> RuleCandidateReport {
        let fallbackRuleID: String? = ComicSiteRuleV2Validator()
            .validate(rule: source.rule)
            .resolvedRule?
            .primaryDetailEntry?
            .detailRuleID
        return try self.report(
            html: html,
            source: source,
            operation: .detail,
            pageID: pageID,
            ruleID: detailRule?.id ?? fallbackRuleID,
            url: url,
            candidateScope: .content
        )
    }

    func analyzeReader(
        html: String,
        source: Source,
        galleryRule: GalleryRule?,
        pageID: String?,
        url: String?
    ) throws -> RuleCandidateReport {
        let fallbackRuleID: String? = ComicSiteRuleV2Validator()
            .validate(rule: source.rule)
            .resolvedRule?
            .primaryReaderEntry?
            .galleryRuleID
        return try self.report(
            html: html,
            source: source,
            operation: .reader,
            pageID: pageID,
            ruleID: galleryRule?.id ?? fallbackRuleID,
            url: url,
            candidateScope: .content
        )
    }

    func analyzePagination(
        html: String,
        source: Source,
        pagination: PaginationRule?,
        stage: RuleAnalysisStage,
        pageID: String?,
        ruleID: String?,
        currentURL: String?,
        urlTemplate: String?
    ) throws -> RuleCandidateReport {
        return try self.report(
            html: html,
            source: source,
            operation: stage.sourceRuntimeOperation,
            pageID: pageID,
            ruleID: ruleID,
            url: currentURL,
            pagination: pagination,
            urlTemplate: urlTemplate,
            candidateScope: .pagination
        )
    }

    private func report(
        html: String,
        source: Source,
        operation: BrowseCraftCore.SourceRuntimeOperation,
        pageID: String?,
        ruleID: String?,
        url: String?,
        pagination: PaginationRule? = nil,
        urlTemplate: String? = nil,
        candidateScope: BrowseCraftCore.SourceDiscoveryCandidateScope
    ) throws -> RuleCandidateReport {
        let pageURL = try self.pageURL(url ?? source.baseURL)
        let analysis = try self.analyzer.analyze(
            BrowseCraftCore.SourceDiscoveryAnalysisInput(
                document: BrowseCraftCore.SourceContentDocument(
                    data: Data(html.utf8),
                    finalURL: pageURL,
                    format: .html,
                    mediaType: "text/html"
                ),
                sourceID: source.id,
                sourceName: source.name,
                operation: operation,
                pageID: pageID,
                ruleID: ruleID,
                pagination: pagination,
                urlTemplate: urlTemplate,
                candidateScope: candidateScope
            )
        )
        guard let report = analysis.candidateReport else {
            throw BrowseCraftCore.SourceParsingError.parserFailure(
                reason: "Source Discovery did not produce a candidate report."
            )
        }
        return report
    }

    private func pageURL(_ value: String) throws -> URL {
        guard let url = URL(string: value) else {
            throw BrowseCraftCore.SourceParsingError.invalidInput(
                reason: "Source Discovery requires a valid page URL."
            )
        }
        return url
    }
}
