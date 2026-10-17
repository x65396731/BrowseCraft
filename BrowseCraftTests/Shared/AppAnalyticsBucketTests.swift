import Foundation
import Testing
@testable import BrowseCraft

/// 埋点参数只报枚举、分桶与哈希（`BCA-OBS-002`）：分桶档位与 snake_case 转换是上报口径，改了就是改报表。
struct AppAnalyticsBucketTests {
    @Test func countBucketsFollowTheDictionary() {
        #expect(AppAnalytics.countBucket(0) == "0")
        #expect(AppAnalytics.countBucket(1) == "1_5")
        #expect(AppAnalytics.countBucket(5) == "1_5")
        #expect(AppAnalytics.countBucket(6) == "6_20")
        #expect(AppAnalytics.countBucket(50) == "21_50")
        #expect(AppAnalytics.countBucket(51) == "51_plus")
    }

    @Test func durationBucketsReachPastTwoHours() {
        #expect(AppAnalytics.durationBucket(30) == "lt_1m")
        #expect(AppAnalytics.durationBucket(4 * 60) == "1_5m")
        #expect(AppAnalytics.durationBucket(59 * 60) == "30_60m")
        #expect(AppAnalytics.durationBucket(90 * 60) == "60_120m")
        #expect(AppAnalytics.durationBucket(3 * 3600) == "gt_120m")
    }

    @Test func sizeBucketsUseMegabytes() {
        #expect(AppAnalytics.sizeBucket(bytes: 5 * 1_048_576) == "lt_10mb")
        #expect(AppAnalytics.sizeBucket(bytes: 600 * 1_048_576) == "gt_500mb")
    }

    @Test func errorCodesAreSnakeCased() {
        #expect(AnalyticsErrorCode.snakeCased("requestFailed") == "request_failed")
        #expect(AnalyticsErrorCode.snakeCased("comic-detail-error") == "comic_detail_error")
        #expect(AnalyticsErrorCode.snakeCased("videoPlayback") == "video_playback")
        #expect(AnalyticsErrorCode.snakeCased("unsafeURL") == "unsafe_url")
        #expect(AnalyticsErrorCode.snakeCased("URLPath") == "url_path")
        #expect(AnalyticsErrorCode.snakeCased("already_snake") == "already_snake")
        #expect(AnalyticsErrorCode(StartupOutcome.timedOut).value == "timed_out")
    }

    @Test func everyEventNameFitsFirebaseLimits() {
        for event: AppAnalytics.Event in AppAnalytics.Event.allCases {
            #expect(event.rawValue.count <= 40)
            #expect(event.rawValue.first?.isLetter == true)
        }
        #expect(AppAnalytics.Event.allCases.count == Set(AppAnalytics.Event.allCases.map(\.rawValue)).count)
    }
}
