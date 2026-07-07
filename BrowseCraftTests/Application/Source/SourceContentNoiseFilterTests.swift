import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft

struct SourceContentNoiseFilterTests {
    @Test func discardsObviousAdvertisingListItem() throws {
        let filter: SourceContentNoiseFilter = SourceContentNoiseFilter()
        let decision: SourceContentNoiseDecision = filter.decision(
            for: SourceContentNoiseCandidate(
                title: "Sponsored banner",
                url: try #require(URL(string: "https://ads.example.test/campaign")),
                text: "Install app now",
                cssClass: "ad-banner sponsored",
                elementID: "top-ad",
                tagName: "article",
                sourceKind: .video,
                context: .listItem
            )
        )

        #expect(decision.action == .discard)
        #expect(decision.reasons.contains(.advertising))
    }

    @Test func keepsPlaybackIframeEvenWhenEmbedTextIsPresent() throws {
        let filter: SourceContentNoiseFilter = SourceContentNoiseFilter()
        let decision: SourceContentNoiseDecision = filter.decision(
            for: SourceContentNoiseCandidate(
                title: nil,
                url: try #require(URL(string: "https://player.example.test/embed/movie-1")),
                text: nil,
                cssClass: "responsive-player",
                elementID: "main-player",
                tagName: "iframe",
                attributes: [
                    "src": "https://player.example.test/embed/movie-1",
                    "allowfullscreen": "true"
                ],
                sourceKind: .video,
                context: .playbackCandidate
            )
        )

        #expect(decision.action == .keep)
    }

    @Test func discardsTrackingPlaybackIframe() throws {
        let filter: SourceContentNoiseFilter = SourceContentNoiseFilter()
        let decision: SourceContentNoiseDecision = filter.decision(
            for: SourceContentNoiseCandidate(
                title: nil,
                url: try #require(URL(string: "https://analytics.example.test/pixel")),
                text: nil,
                cssClass: "tracking-pixel",
                elementID: "analytics-frame",
                tagName: "iframe",
                attributes: [
                    "src": "https://analytics.example.test/pixel"
                ],
                sourceKind: .video,
                context: .playbackCandidate
            )
        )

        #expect(decision.action == .discard)
        #expect(decision.reasons.contains(.tracking))
    }

    @Test func discardsAccountNavigationListItem() throws {
        let filter: SourceContentNoiseFilter = SourceContentNoiseFilter()
        let decision: SourceContentNoiseDecision = filter.decision(
            for: SourceContentNoiseCandidate(
                title: "登录",
                url: try #require(URL(string: "https://video.example.test/login")),
                text: "登录",
                cssClass: "account-link",
                elementID: nil,
                tagName: "a",
                sourceKind: .video,
                context: .listItem
            )
        )

        #expect(decision.action == .discard)
        #expect(decision.reasons.contains(.accountNavigation))
    }
}
