import Foundation

// 中文注释：ResolveReaderSourcePresentationUseCase 是 Reader 展示层边界，不执行 rule runtime。
struct ResolveReaderSourcePresentationUseCase {
    func readerImageRequestConfig(for source: Source) -> RequestConfig? {
        guard let rule: SiteRule = source.ruleConfiguration?.rule else {
            return nil
        }

        return ComicSiteRuleV2Validator()
            .validate(rule: rule)
            .resolvedRule?
            .primaryReaderEntry?
            .effectiveRequest
    }

    func detailCoverRequestConfig(for source: Source) -> RequestConfig? {
        guard let rule: SiteRule = source.ruleConfiguration?.rule else {
            return nil
        }

        return ComicSiteRuleV2Validator()
            .validate(rule: rule)
            .resolvedRule?
            .primaryDetailEntry?
            .effectiveRequest
    }
}
