import Foundation
import BrowseCraftCore

// 中文注释：SourceImportRecommendationUseCase.swift 为添加来源流程提供本地启发式推荐，不执行网络抓取。

struct SourceImportRecommendationUseCase {
    func execute(
        draft: SourceImportDraft,
        selectedOptionKind: SourceImportOptionKind? = nil,
        html: String? = nil,
        headers: [String: String] = [:]
    ) -> SourceImportRecommendation {
        if let selectedOptionKind: SourceImportOptionKind {
            return self.executeSelectedOption(
                selectedOptionKind,
                draft: draft,
                html: html,
                headers: headers
            )
        }

        if draft.trimmedRuleJSON != nil {
            return SourceImportRecommendation(
                optionKind: .websiteRuleJSON,
                sourceType: .json,
                configurationKind: .comic,
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
                sourceType: .rss,
                configurationKind: .rss,
                confidence: .high,
                reasons: [.urlLooksLikeRSS]
            )
        }

        if Self.headersLookLikeRSS(normalizedHeaders) {
            return SourceImportRecommendation(
                optionKind: .rssFeedURL,
                sourceType: .rss,
                configurationKind: .rss,
                confidence: .high,
                reasons: [.headerLooksLikeRSS]
            )
        }

        if Self.htmlContainsRSSLink(normalizedHTML) {
            return SourceImportRecommendation(
                optionKind: .rssFeedURL,
                sourceType: .rss,
                configurationKind: .rss,
                confidence: .medium,
                reasons: [.htmlContainsRSSLink],
                warnings: ["The page links to a feed; confirm the feed URL before saving."]
            )
        }

        if Self.htmlContainsVideoElement(normalizedHTML) {
            return SourceImportRecommendation(
                optionKind: .videoSource,
                sourceType: .html,
                configurationKind: .video,
                confidence: .medium,
                reasons: [.htmlContainsVideoElement],
                warnings: ["Video sources are routed through the video runtime entry."]
            )
        }

        if Self.isKnownRuleTemplateURL(normalizedURL) {
            return SourceImportRecommendation(
                optionKind: .comicSource,
                sourceType: .html,
                configurationKind: .comic,
                confidence: .high,
                reasons: [.knownRuleTemplate]
            )
        }

        return SourceImportRecommendation(
            optionKind: .comicSource,
            sourceType: .html,
            configurationKind: .comic,
            confidence: .low,
            reasons: [.userSelectedOption],
            warnings: ["No specific source format was detected yet."]
        )
    }

    private func executeSelectedOption(
        _ selectedOptionKind: SourceImportOptionKind,
        draft: SourceImportDraft,
        html: String?,
        headers: [String: String]
    ) -> SourceImportRecommendation {
        let normalizedURL: String = draft.trimmedEntryURL.lowercased()
        let normalizedHeaders: [String: String] = Self.normalized(headers)

        switch selectedOptionKind {
        case .rssFeedURL:
            let urlLooksLikeRSS: Bool = Self.looksLikeRSSURL(normalizedURL)
            let headersLookLikeRSS: Bool = Self.headersLookLikeRSS(normalizedHeaders)
            if urlLooksLikeRSS || headersLookLikeRSS {
                let formatReason: SourceImportRecommendationReason = urlLooksLikeRSS ? .urlLooksLikeRSS : .headerLooksLikeRSS
                return SourceImportRecommendation(
                    optionKind: .rssFeedURL,
                    sourceType: .rss,
                    configurationKind: .rss,
                    confidence: .high,
                    reasons: [.userSelectedOption, formatReason]
                )
            }

            return SourceImportRecommendation(
                optionKind: .rssFeedURL,
                sourceType: .rss,
                configurationKind: .rss,
                confidence: .low,
                reasons: [.userSelectedOption],
                warnings: ["This URL does not look like an RSS feed."]
            )
        case .comicSource:
            return SourceImportRecommendation(
                optionKind: .comicSource,
                sourceType: .html,
                configurationKind: .comic,
                confidence: .medium,
                reasons: [.userSelectedOption],
                warnings: ["Comic sources use Website Rule JSON under the hood."]
            )
        case .videoSource:
            return SourceImportRecommendation(
                optionKind: .videoSource,
                sourceType: .html,
                configurationKind: .video,
                confidence: .medium,
                reasons: [.userSelectedOption],
                warnings: ["Video sources use the video runtime and currently support MacCMS-style pages first."]
            )
        case .websiteRuleJSON, .rulePackageJSON, .scriptSource:
            return self.execute(draft: draft, html: html, headers: headers)
        }
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
