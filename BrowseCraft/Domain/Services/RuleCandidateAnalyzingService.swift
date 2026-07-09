import Foundation

// RuleCandidateAnalyzingService keeps candidate discovery behind a domain-facing protocol.

protocol RuleCandidateAnalyzingService {
    func analyzeList(
        html: String,
        source: Source,
        listRule: ListRule?,
        pageID: String?,
        url: String?
    ) throws -> RuleCandidateReport

    func analyzeDetail(
        html: String,
        source: Source,
        detailRule: DetailRule?,
        pageID: String?,
        url: String?
    ) throws -> RuleCandidateReport

    func analyzeReader(
        html: String,
        source: Source,
        galleryRule: GalleryRule?,
        pageID: String?,
        url: String?
    ) throws -> RuleCandidateReport

    func analyzePagination(
        html: String,
        source: Source,
        pagination: PaginationRule?,
        stage: RuleAnalysisStage,
        pageID: String?,
        ruleID: String?,
        currentURL: String?,
        urlTemplate: String?
    ) throws -> RuleCandidateReport
}
