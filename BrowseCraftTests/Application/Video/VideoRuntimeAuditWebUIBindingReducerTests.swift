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

    // 中文注释：播放器解锁自动播放用的内联 data: 假视频没有网络请求，不参与绑定（kinogo 实测）。
    @Test func dataURIDummyOnlyIsMissingButStarted() {
        let observation = VideoRuntimeAuditWebUIBindingReducer.reduce(
            events: [
                VideoRuntimeAuditMediaPlayingEvent(
                    elementID: "unlock:1",
                    currentSrc: "data:video/mp4;base64,AAAAIGZ0eXBpc29t"
                )
            ],
            timedOut: true
        )
        #expect(observation.playerStarted == true)
        #expect(observation.bindingStatus == .missing)
        #expect(observation.mediaURL == nil)
    }

    @Test func dataURIDummyDoesNotMakeRealSourceAmbiguous() {
        let observation = VideoRuntimeAuditWebUIBindingReducer.reduce(
            events: [
                VideoRuntimeAuditMediaPlayingEvent(
                    elementID: "unlock:1",
                    currentSrc: "data:video/mp4;base64,AAAAIGZ0eXBpc29t"
                ),
                VideoRuntimeAuditMediaPlayingEvent(
                    elementID: "player:1",
                    currentSrc: "https://cdn.example.invalid/hls/master.m3u8"
                )
            ],
            timedOut: false
        )
        #expect(observation.bindingStatus == .unique)
        #expect(observation.mediaURL?.host == "cdn.example.invalid")
    }

    @Test func bindingCandidatePredicateExcludesDataAndEmpty() {
        #expect(VideoRuntimeAuditWebUIBindingReducer.isBindingCandidate("https://a.invalid/x.m3u8"))
        #expect(VideoRuntimeAuditWebUIBindingReducer.isBindingCandidate("blob:https://a.invalid/1"))
        #expect(VideoRuntimeAuditWebUIBindingReducer.isBindingCandidate("DATA:video/mp4;base64,AA") == false)
        #expect(VideoRuntimeAuditWebUIBindingReducer.isBindingCandidate("   ") == false)
    }

    // 中文注释：BC-EVIDENCE-078.1——激活选择器只来自 catalog 声明的 css 选择器。
    @Test func activationSelectorOnlyAcceptsDeclaredCSS() {
        #expect(VideoRuntimeAuditActivationSelector.cssSelector(selector: "li.current[data-src]", selectorKind: "css") == "li.current[data-src]")
        #expect(VideoRuntimeAuditActivationSelector.cssSelector(selector: " li.current ", selectorKind: nil) == "li.current")
        #expect(VideoRuntimeAuditActivationSelector.cssSelector(selector: "//li", selectorKind: "xpath") == nil)
        #expect(VideoRuntimeAuditActivationSelector.cssSelector(selector: "", selectorKind: "css") == nil)
        #expect(VideoRuntimeAuditActivationSelector.cssSelector(selector: nil, selectorKind: "css") == nil)
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
