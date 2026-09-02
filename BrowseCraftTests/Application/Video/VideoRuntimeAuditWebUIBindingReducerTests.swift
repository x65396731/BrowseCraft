import Foundation
import Testing
@testable import BrowseCraft

// 中文注释：BC-EVIDENCE-077.3 / BC-EVIDENCE-021 的操作化归约——纯函数，不触网、不建 WebView。
struct VideoRuntimeAuditWebUIBindingReducerTests {
    @Test func noPlayingEventIsMissingAndNotStarted() {
        let observation = VideoRuntimeAuditWebUIBindingReducer.reduce(events: [], timedOut: true)
        #expect(observation.playerStarted == false)
        #expect(observation.bindingStatus == .missing)
        #expect(observation.mediaURL == nil)
        #expect(observation.timedOut == true)
    }

    @Test func singleElementWithHTTPSourceIsUnique() {
        let observation = VideoRuntimeAuditWebUIBindingReducer.reduce(
            events: [
                VideoRuntimeAuditMediaPlayingEvent(
                    elementID: "f1:1",
                    currentSrc: "https://cdn.example.invalid/hls/master.m3u8?token=x"
                ),
                // 中文注释：同一元素重复上报 playing（暂停后继续）不改变绑定。
                VideoRuntimeAuditMediaPlayingEvent(
                    elementID: "f1:1",
                    currentSrc: "https://cdn.example.invalid/hls/master.m3u8?token=x"
                )
            ],
            timedOut: false
        )
        #expect(observation.playerStarted == true)
        #expect(observation.bindingStatus == .unique)
        #expect(observation.mediaURL?.host == "cdn.example.invalid")
    }

    @Test func blobSourceIsMissingEvenThoughPlayerStarted() {
        let observation = VideoRuntimeAuditWebUIBindingReducer.reduce(
            events: [
                VideoRuntimeAuditMediaPlayingEvent(
                    elementID: "f1:1",
                    currentSrc: "blob:https://player.example.invalid/3f2a"
                )
            ],
            timedOut: false
        )
        #expect(observation.playerStarted == true)
        #expect(observation.bindingStatus == .missing)
        #expect(observation.mediaURL == nil)
    }

    @Test func twoElementsWithDifferentSourcesAreAmbiguous() {
        let observation = VideoRuntimeAuditWebUIBindingReducer.reduce(
            events: [
                VideoRuntimeAuditMediaPlayingEvent(
                    elementID: "ad:1",
                    currentSrc: "https://ads.example.invalid/pre.mp4"
                ),
                VideoRuntimeAuditMediaPlayingEvent(
                    elementID: "f1:1",
                    currentSrc: "https://cdn.example.invalid/hls/master.m3u8"
                )
            ],
            timedOut: false
        )
        #expect(observation.playerStarted == true)
        #expect(observation.bindingStatus == .ambiguous)
        #expect(observation.mediaURL == nil)
    }

    @Test func twoElementsSharingOneSourceStayUnique() {
        let observation = VideoRuntimeAuditWebUIBindingReducer.reduce(
            events: [
                VideoRuntimeAuditMediaPlayingEvent(
                    elementID: "f1:1",
                    currentSrc: "https://cdn.example.invalid/clip.mp4"
                ),
                VideoRuntimeAuditMediaPlayingEvent(
                    elementID: "f2:1",
                    currentSrc: "https://cdn.example.invalid/clip.mp4"
                )
            ],
            timedOut: false
        )
        #expect(observation.bindingStatus == .unique)
    }

    @Test func emptySourceIsMissing() {
        let observation = VideoRuntimeAuditWebUIBindingReducer.reduce(
            events: [VideoRuntimeAuditMediaPlayingEvent(elementID: "f1:1", currentSrc: "")],
            timedOut: false
        )
        #expect(observation.playerStarted == true)
        #expect(observation.bindingStatus == .missing)
    }
}
