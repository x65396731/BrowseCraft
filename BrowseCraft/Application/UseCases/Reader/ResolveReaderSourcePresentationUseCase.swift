import BrowseCraftCore
import BrowseCraftDomain
import Foundation

// 中文注释：ResolveReaderSourcePresentationUseCase 是 Reader 展示层边界，不执行 rule runtime。
struct ResolveReaderSourcePresentationUseCase {
    // 中文注释：两段分开（2026-10-20 审计 C-1）：`*RuleRequestConfig(for:)` 要跑一遍 2.5k 行的规则校验器，贵，
    // ViewModel 按 source 算一次存起来；`imageRequestConfig(for:ruleRequestConfig:)` 只套 UA 选择，便宜，
    // 每次读都重新套——`BCA-RUNTIME-010` 的 UA 选择会在会话中途变，不能一起缓存。

    /// 规则声明的阅读页图片请求（不含 UA 选择）。
    func readerRuleRequestConfig(for source: Source) -> RequestConfig? {
        guard let rule: SiteRule = source.ruleConfiguration?.rule else {
            return nil
        }
        return ComicSiteRuleV2Validator()
            .validate(rule: rule)
            .resolvedRule?
            .primaryReaderEntry?
            .effectiveRequest
    }

    /// 规则声明的详情页封面请求（不含 UA 选择）。
    func detailCoverRuleRequestConfig(for source: Source) -> RequestConfig? {
        guard let rule: SiteRule = source.ruleConfiguration?.rule else {
            return nil
        }
        return ComicSiteRuleV2Validator()
            .validate(rule: rule)
            .resolvedRule?
            .primaryDetailEntry?
            .effectiveRequest
    }

    /// 中文注释：`BCA-RUNTIME-010` 修订——图片跟随来源的 UA 选择（同 `ResolveLibrarySourcePresentationUseCase.imageRequestConfig`）。
    func imageRequestConfig(for source: Source, ruleRequestConfig: RequestConfig?) -> RequestConfig? {
        return SourceUserAgentFallback.shared.applyingImageUserAgent(to: ruleRequestConfig, sourceID: source.id)
    }

    func readerImageRequestConfig(for source: Source) -> RequestConfig? {
        return self.imageRequestConfig(for: source, ruleRequestConfig: self.readerRuleRequestConfig(for: source))
    }

    func detailCoverRequestConfig(for source: Source) -> RequestConfig? {
        return self.imageRequestConfig(for: source, ruleRequestConfig: self.detailCoverRuleRequestConfig(for: source))
    }
}
