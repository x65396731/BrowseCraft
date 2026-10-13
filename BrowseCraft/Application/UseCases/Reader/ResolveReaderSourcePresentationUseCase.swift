import BrowseCraftCore
import BrowseCraftDomain
import Foundation

// 中文注释：ResolveReaderSourcePresentationUseCase 是 Reader 展示层边界，不执行 rule runtime。
struct ResolveReaderSourcePresentationUseCase {
    func readerImageRequestConfig(for source: Source) -> RequestConfig? {
        // 中文注释：`BCA-RUNTIME-010` 修订——图片跟随来源的 UA 选择（同 `ResolveLibrarySourcePresentationUseCase.imageRequestConfig`）。
        guard let rule: SiteRule = source.ruleConfiguration?.rule else {
            return SourceUserAgentFallback.shared.applyingImageUserAgent(to: nil, sourceID: source.id)
        }

        let ruleConfig: RequestConfig? = ComicSiteRuleV2Validator()
            .validate(rule: rule)
            .resolvedRule?
            .primaryReaderEntry?
            .effectiveRequest
        return SourceUserAgentFallback.shared.applyingImageUserAgent(to: ruleConfig, sourceID: source.id)
    }

    func detailCoverRequestConfig(for source: Source) -> RequestConfig? {
        guard let rule: SiteRule = source.ruleConfiguration?.rule else {
            return SourceUserAgentFallback.shared.applyingImageUserAgent(to: nil, sourceID: source.id)
        }

        let ruleConfig: RequestConfig? = ComicSiteRuleV2Validator()
            .validate(rule: rule)
            .resolvedRule?
            .primaryDetailEntry?
            .effectiveRequest
        return SourceUserAgentFallback.shared.applyingImageUserAgent(to: ruleConfig, sourceID: source.id)
    }
}
