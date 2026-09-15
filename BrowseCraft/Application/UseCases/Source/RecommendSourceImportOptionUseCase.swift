import Foundation
import BrowseCraftCore

// 中文注释：根据 Add Source 表单输入和可选页面线索，推荐 Video/Rule 等导入选项；本用例不执行网络抓取。

struct RecommendSourceImportOptionUseCase {
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

        let normalizedURL: String = draft.trimmedEntryURL.lowercased()
        let normalizedHTML: String = html?.lowercased() ?? ""

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
        switch selectedOptionKind {
        case .comicSource:
            return SourceImportRecommendation(
                optionKind: .comicSource,
                sourceType: .html,
                configurationKind: .comic,
                confidence: .medium,
                reasons: [.userSelectedOption],
                warnings: ["Comic sources use the rule-backed source runtime."]
            )
        case .bookSource:
            return SourceImportRecommendation(
                optionKind: .bookSource,
                sourceType: .html,
                configurationKind: .book,
                confidence: .medium,
                reasons: [.userSelectedOption],
                warnings: ["Book sources use the rule-backed source runtime."]
            )
        case .videoSource:
            return SourceImportRecommendation(
                optionKind: .videoSource,
                sourceType: .html,
                configurationKind: .video,
                confidence: .medium,
                reasons: [.userSelectedOption],
                warnings: ["Video sources must come from a validated VideoSiteRule V2 catalog entry."]
            )
        case .scriptSource:
            return self.execute(draft: draft, html: html, headers: headers)
        }
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
