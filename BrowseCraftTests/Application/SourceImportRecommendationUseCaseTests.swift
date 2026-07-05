import Foundation
import BrowseCraftCore
import Testing
@testable import BrowseCraft

// 中文注释：SourceImportRecommendationUseCaseTests 固定 P4.6 添加来源推荐启发式边界。
struct SourceImportRecommendationUseCaseTests {
    @Test func rssLookingURLRecommendsRSSFeed() {
        let useCase: SourceImportRecommendationUseCase = SourceImportRecommendationUseCase()
        let draft: SourceImportDraft = SourceImportDraft(entryURL: "https://example.test/feed.xml")

        let recommendation: SourceImportRecommendation = useCase.execute(draft: draft)

        #expect(recommendation.optionKind == .rssFeedURL)
        #expect(recommendation.contentType == .article)
        #expect(recommendation.sourceType == .rss)
        #expect(recommendation.configurationKind == .rss)
        #expect(recommendation.confidence == .high)
        #expect(recommendation.reasons == [.urlLooksLikeRSS])
    }

    @Test func rssContentTypeHeaderRecommendsRSSFeed() {
        let useCase: SourceImportRecommendationUseCase = SourceImportRecommendationUseCase()
        let draft: SourceImportDraft = SourceImportDraft(entryURL: "https://example.test/latest")

        let recommendation: SourceImportRecommendation = useCase.execute(
            draft: draft,
            headers: ["Content-Type": "application/rss+xml; charset=utf-8"]
        )

        #expect(recommendation.optionKind == .rssFeedURL)
        #expect(recommendation.configurationKind == .rss)
        #expect(recommendation.reasons == [.headerLooksLikeRSS])
    }

    @Test func rssLinkInHTMLRecommendsFeedWithMediumConfidence() {
        let useCase: SourceImportRecommendationUseCase = SourceImportRecommendationUseCase()
        let draft: SourceImportDraft = SourceImportDraft(entryURL: "https://example.test")
        let html: String = """
        <html>
          <head>
            <link rel="alternate" type="application/rss+xml" href="/feed.xml">
          </head>
        </html>
        """

        let recommendation: SourceImportRecommendation = useCase.execute(draft: draft, html: html)

        #expect(recommendation.optionKind == .rssFeedURL)
        #expect(recommendation.confidence == .medium)
        #expect(recommendation.reasons == [.htmlContainsRSSLink])
        #expect(recommendation.warnings.isEmpty == false)
    }

    @Test func videoHTMLRecommendsWebsiteRuleWithoutForcingVideoRuntime() {
        let useCase: SourceImportRecommendationUseCase = SourceImportRecommendationUseCase()
        let draft: SourceImportDraft = SourceImportDraft(entryURL: "https://video.example.test")
        let html: String = "<html><body><video src=\"movie.mp4\"></video></body></html>"

        let recommendation: SourceImportRecommendation = useCase.execute(draft: draft, html: html)

        #expect(recommendation.optionKind == .websiteURL)
        #expect(recommendation.contentType == .video)
        #expect(recommendation.sourceType == .html)
        #expect(recommendation.configurationKind == .rule)
        #expect(recommendation.reasons == [.htmlContainsVideoElement])
        #expect(recommendation.warnings == ["Video sites can still be parsed by a website rule."])
    }

    @Test func knownRuleTemplateURLRecommendsRuleBackedComicSource() {
        let useCase: SourceImportRecommendationUseCase = SourceImportRecommendationUseCase()
        let draft: SourceImportDraft = SourceImportDraft(entryURL: "https://mycomic.com/cn")

        let recommendation: SourceImportRecommendation = useCase.execute(draft: draft)

        #expect(recommendation.optionKind == .websiteURL)
        #expect(recommendation.contentType == .comic)
        #expect(recommendation.configurationKind == .rule)
        #expect(recommendation.confidence == .high)
        #expect(recommendation.reasons == [.knownRuleTemplate])
    }

    @Test func unknownWebsiteFallsBackToLowConfidenceRuleRecommendation() {
        let useCase: SourceImportRecommendationUseCase = SourceImportRecommendationUseCase()
        let draft: SourceImportDraft = SourceImportDraft(entryURL: "https://unknown.example.test")

        let recommendation: SourceImportRecommendation = useCase.execute(draft: draft)

        #expect(recommendation.optionKind == .websiteURL)
        #expect(recommendation.sourceType == .html)
        #expect(recommendation.configurationKind == .rule)
        #expect(recommendation.confidence == .low)
        #expect(recommendation.reasons == [.userSelectedOption])
    }
}
