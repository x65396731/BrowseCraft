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
        let filter: SourceContentNoiseFilter = SourceContentNoiseFilter(
            lexicon: SourceDetectionLexicon.load(language: .simplifiedChinese)
        )
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

    @Test func discardsRedirectNavigationWithAdSignals() throws {
        let filter: SourceContentNoiseFilter = SourceContentNoiseFilter()
        let decision: SourceContentNoiseDecision = filter.decision(
            for: SourceContentNoiseCandidate(
                url: try #require(
                    URL(
                        string: "https://video.example.test/redirect?" +
                            "utm_source=banner&target=https%3A%2F%2Fpromo.example.test%2Fpopup"
                    )
                ),
                context: .playbackCandidate
            )
        )

        #expect(decision.action == .discard)
        #expect(decision.reasons.contains(.navigationReject))
    }

    @Test func keepsPlaybackNavigationEvenWithPromoQuery() throws {
        let filter: SourceContentNoiseFilter = SourceContentNoiseFilter()
        let decision: SourceContentNoiseDecision = filter.decision(
            for: SourceContentNoiseCandidate(
                url: try #require(
                    URL(
                        string: "https://video.example.test/player/embed/movie-1?" +
                            "utm_source=promo&ref=homepage"
                    )
                ),
                attributes: [
                    "src": "https://video.example.test/player/embed/movie-1"
                ],
                context: .playbackCandidate
            )
        )

        #expect(decision.action == .keep)
    }

    // 中文注释：`BC-EVIDENCE-071`。规则匹配到的媒体候选，其 path 必然含 m3u8/mp4——
    // 那正是它被选中的原因。把它当播放证据会让广告豁免恒成立，过滤器对媒体候选完全惰性。
    @Test func ruleDeclaredMediaCandidateEarnsNoAdvertisingExemptionFromItsOwnExtension() throws {
        let filter: SourceContentNoiseFilter = SourceContentNoiseFilter()
        let advertisingMediaURL: URL = try #require(
            URL(string: "https://cdn.example.test/ads/preroll/spot.m3u8")
        )

        let inferred: SourceContentNoiseDecision = filter.decision(
            for: SourceContentNoiseCandidate(
                url: advertisingMediaURL,
                sourceKind: .video,
                context: .playbackCandidate
            )
        )
        let ruleDeclared: SourceContentNoiseDecision = filter.decision(
            for: SourceContentNoiseCandidate(
                url: advertisingMediaURL,
                sourceKind: .video,
                playbackAssurance: .ruleDeclared,
                context: .playbackCandidate
            )
        )

        #expect(inferred.action == .keep)
        #expect(ruleDeclared.action == .discard)
        #expect(ruleDeclared.reasons.contains(.advertising))
    }

    @Test func discardsRuleDeclaredMediaCandidateOnAdvertisingHost() throws {
        let filter: SourceContentNoiseFilter = SourceContentNoiseFilter()
        let decision: SourceContentNoiseDecision = filter.decision(
            for: SourceContentNoiseCandidate(
                url: try #require(URL(string: "https://adserver.example.test/vast/preroll.m3u8")),
                sourceKind: .video,
                playbackAssurance: .ruleDeclared,
                context: .playbackCandidate
            )
        )

        #expect(decision.action == .discard)
    }

    // 中文注释：`BC-EVIDENCE-072`。签名 token 会随机命中 "ad-"/"-ad"/"_ad" 这类短标记；
    // query 只由结构化计分判别，不参与词表子串匹配。
    @Test func keepsRuleDeclaredMediaCandidateWhoseSignedQueryContainsAdMarker() throws {
        let filter: SourceContentNoiseFilter = SourceContentNoiseFilter()
        let decision: SourceContentNoiseDecision = filter.decision(
            for: SourceContentNoiseCandidate(
                url: try #require(
                    URL(
                        string: "https://media.example.test/mp43/864729.mp4?"
                            + "st=4p5tNZQpVWVWyy3QAD-55w&e=1787275282"
                    )
                ),
                sourceKind: .video,
                playbackAssurance: .ruleDeclared,
                context: .playbackCandidate
            )
        )

        #expect(decision.action == .keep)
    }

    @Test func keepsRuleDeclaredPlainMediaCandidate() throws {
        let filter: SourceContentNoiseFilter = SourceContentNoiseFilter()
        let decision: SourceContentNoiseDecision = filter.decision(
            for: SourceContentNoiseCandidate(
                url: try #require(URL(string: "https://cdn.example.test/hls/61610/index.m3u8")),
                sourceKind: .video,
                playbackAssurance: .ruleDeclared,
                context: .playbackCandidate
            )
        )

        #expect(decision.action == .keep)
    }
}
