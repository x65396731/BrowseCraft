import Foundation
import BrowseCraftCore

// 中文注释：SourceImportRecommendationUseCase.swift 为添加来源流程提供本地启发式推荐，不执行网络抓取。

struct SourceImportRecommendationUseCase {
    func execute(
        draft: SourceImportDraft,
        html: String? = nil,
        headers: [String: String] = [:]
    ) -> SourceImportRecommendation {
        if draft.trimmedRuleJSON != nil {
            return SourceImportRecommendation(
                optionKind: .websiteRuleJSON,
                sourceType: .json,
                configurationKind: .rule,
                confidence: .high,
                reasons: [.ruleJSONDetected]
            )
        }

        let normalizedURL: String = draft.trimmedEntryURL.lowercased()
        let normalizedHTML: String = html?.lowercased() ?? ""
        let normalizedHeaders: [String: String] = Self.normalized(headers)

        if Self.looksLikeRSSURL(normalizedURL) {
            return SourceImportRecommendation(
                optionKind: .rssFeedURL,
                contentType: .article,
                sourceType: .rss,
                configurationKind: .rss,
                confidence: .high,
                reasons: [.urlLooksLikeRSS]
            )
        }

        if Self.headersLookLikeRSS(normalizedHeaders) {
            return SourceImportRecommendation(
                optionKind: .rssFeedURL,
                contentType: .article,
                sourceType: .rss,
                configurationKind: .rss,
                confidence: .high,
                reasons: [.headerLooksLikeRSS]
            )
        }

        if Self.htmlContainsRSSLink(normalizedHTML) {
            return SourceImportRecommendation(
                optionKind: .rssFeedURL,
                contentType: .article,
                sourceType: .rss,
                configurationKind: .rss,
                confidence: .medium,
                reasons: [.htmlContainsRSSLink],
                warnings: ["The page links to a feed; confirm the feed URL before saving."]
            )
        }

        if Self.htmlContainsVideoElement(normalizedHTML) {
            return SourceImportRecommendation(
                optionKind: .websiteURL,
                contentType: .video,
                sourceType: .html,
                configurationKind: .rule,
                confidence: .medium,
                reasons: [.htmlContainsVideoElement],
                warnings: ["Video sites can still be parsed by a website rule."]
            )
        }

        if Self.isKnownRuleTemplateURL(normalizedURL) {
            return SourceImportRecommendation(
                optionKind: .websiteURL,
                contentType: .comic,
                sourceType: .html,
                configurationKind: .rule,
                confidence: .high,
                reasons: [.knownRuleTemplate]
            )
        }

        return SourceImportRecommendation(
            optionKind: .websiteURL,
            sourceType: .html,
            configurationKind: .rule,
            confidence: .low,
            reasons: [.userSelectedOption],
            warnings: ["No specific source format was detected yet."]
        )
    }

    private static func normalized(_ headers: [String: String]) -> [String: String] {
        var normalizedHeaders: [String: String] = [:]
        headers.forEach { key, value in
            normalizedHeaders[key.lowercased()] = value.lowercased()
        }
        return normalizedHeaders
    }

    private static func looksLikeRSSURL(_ url: String) -> Bool {
        return url.hasSuffix(".rss")
            || url.hasSuffix(".xml")
            || url.contains("/rss")
            || url.contains("/feed")
            || url.contains("feed.xml")
    }

    private static func headersLookLikeRSS(_ headers: [String: String]) -> Bool {
        let contentType: String = headers["content-type"] ?? ""
        return contentType.contains("application/rss+xml")
            || contentType.contains("application/atom+xml")
            || contentType.contains("application/xml")
            || contentType.contains("text/xml")
    }

    private static func htmlContainsRSSLink(_ html: String) -> Bool {
        return html.contains("application/rss+xml")
            || html.contains("application/atom+xml")
            || html.contains("rel=\"alternate\"")
            && html.contains("rss")
    }

    private static func htmlContainsVideoElement(_ html: String) -> Bool {
        return html.contains("<video")
            || html.contains("application/vnd.apple.mpegurl")
            || html.contains("application/x-mpegurl")
    }

    private static func isKnownRuleTemplateURL(_ url: String) -> Bool {
        return url.contains("mycomic.com")
            || url.contains("peppercarrot.com")
    }
}
