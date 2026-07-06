import Foundation
import BrowseCraftCore
import Testing
@testable import BrowseCraft

// 中文注释：SourceImportRecommendationUseCaseTests 固定 P4.6 添加来源推荐启发式边界。
struct SourceImportRecommendationUseCaseTests {
    @Test func rssLookingURLRecommendsRSSFeed() {
        let useCase: RecommendSourceImportOptionUseCase = RecommendSourceImportOptionUseCase()
        let draft: SourceImportDraft = SourceImportDraft(entryURL: "https://example.test/feed.xml")

        let recommendation: SourceImportRecommendation = useCase.execute(
            draft: draft,
            selectedOptionKind: .rssFeedURL
        )

        #expect(recommendation.optionKind == .rssFeedURL)
        #expect(recommendation.sourceType == .rss)
        #expect(recommendation.configurationKind == .rss)
        #expect(recommendation.confidence == .high)
        #expect(recommendation.reasons == [.userSelectedOption, .urlLooksLikeRSS])
    }

    @Test func rssEntryRejectsNonRSSLookingURL() {
        let useCase: RecommendSourceImportOptionUseCase = RecommendSourceImportOptionUseCase()
        let draft: SourceImportDraft = SourceImportDraft(entryURL: "https://example.test/watch/123")

        let recommendation: SourceImportRecommendation = useCase.execute(
            draft: draft,
            selectedOptionKind: .rssFeedURL
        )

        #expect(recommendation.optionKind == .rssFeedURL)
        #expect(recommendation.configurationKind == .rss)
        #expect(recommendation.confidence == .low)
        #expect(recommendation.warnings == ["This URL does not look like an RSS feed."])
    }

    @Test func rssContentTypeHeaderRecommendsRSSFeed() {
        let useCase: RecommendSourceImportOptionUseCase = RecommendSourceImportOptionUseCase()
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
        let useCase: RecommendSourceImportOptionUseCase = RecommendSourceImportOptionUseCase()
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

    @Test func videoHTMLRecommendsVideoRuntimeWithoutRuleFallback() {
        let useCase: RecommendSourceImportOptionUseCase = RecommendSourceImportOptionUseCase()
        let draft: SourceImportDraft = SourceImportDraft(entryURL: "https://video.example.test")
        let html: String = "<html><body><video src=\"movie.mp4\"></video></body></html>"

        let recommendation: SourceImportRecommendation = useCase.execute(draft: draft, html: html)

        #expect(recommendation.optionKind == .videoSource)
        #expect(recommendation.sourceType == .html)
        #expect(recommendation.configurationKind == .video)
        #expect(recommendation.reasons == [.htmlContainsVideoElement])
        #expect(recommendation.warnings == ["Video sources are routed through the video runtime entry."])
    }

    @Test func knownRuleTemplateURLRecommendsComicRuntimeSource() {
        let useCase: RecommendSourceImportOptionUseCase = RecommendSourceImportOptionUseCase()
        let draft: SourceImportDraft = SourceImportDraft(entryURL: "https://mycomic.com/cn")

        let recommendation: SourceImportRecommendation = useCase.execute(draft: draft)

        #expect(recommendation.optionKind == .comicSource)
        #expect(recommendation.sourceType == .html)
        #expect(recommendation.configurationKind == .comic)
        #expect(recommendation.confidence == .high)
        #expect(recommendation.reasons == [.knownRuleTemplate])
    }

    @Test func unknownWebsiteFallsBackToLowConfidenceComicRecommendation() {
        let useCase: RecommendSourceImportOptionUseCase = RecommendSourceImportOptionUseCase()
        let draft: SourceImportDraft = SourceImportDraft(entryURL: "https://unknown.example.test")

        let recommendation: SourceImportRecommendation = useCase.execute(draft: draft)

        #expect(recommendation.optionKind == .comicSource)
        #expect(recommendation.sourceType == .html)
        #expect(recommendation.configurationKind == .comic)
        #expect(recommendation.confidence == .low)
        #expect(recommendation.reasons == [.userSelectedOption])
    }
}
