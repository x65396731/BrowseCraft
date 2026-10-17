import Foundation
import Testing
@testable import BrowseCraft

/// 广告埋点只报类别（设计书 30.8）：四种结局各落一个桶，触发来源取枚举 rawValue。
struct AppAnalyticsAdEventTests {
    @Test func adResultsMapToFourBuckets() {
        #expect(AppAnalytics.adResultBucket(.completed) == "completed")
        #expect(AppAnalytics.adResultBucket(.skipped) == "skipped")
        #expect(AppAnalytics.adResultBucket(.unavailable("GADApplicationIdentifier is missing.")) == "unavailable")
        #expect(AppAnalytics.adResultBucket(.failed("no fill")) == "failed")
    }

    @Test func triggerRawValuesAreTheAnalyticsParameter() {
        #expect(RewardedAdPlaybackTrigger.comic.rawValue == "comic")
        #expect(RewardedAdPlaybackTrigger.video.rawValue == "video")
        #expect(RewardedAdPlaybackTrigger.book.rawValue == "book")
        #expect(RewardedAdPlaybackTrigger.audiobook.rawValue == "audiobook")
        #expect(RewardedAdPlaybackTrigger.manual.rawValue == "manual")
    }

    @Test func generationKindsMapToAnalyticsContentKind() {
        #expect(AnalyticsContentKind(ruleGenerationKind: .video) == .video)
        #expect(AnalyticsContentKind(ruleGenerationKind: .comic) == .comic)
        #expect(AnalyticsContentKind(ruleGenerationKind: .book) == .book)
    }

    @Test func bookScreensAreSnakeCased() {
        #expect(DiagnosticScreen.bookShelf.rawValue == "book_shelf")
        #expect(DiagnosticScreen.bookDetail.rawValue == "book_detail")
        #expect(DiagnosticScreen.bookReader.rawValue == "book_reader")
        #expect(DiagnosticScreen.audiobookPlayer.rawValue == "audiobook_player")
    }
}
