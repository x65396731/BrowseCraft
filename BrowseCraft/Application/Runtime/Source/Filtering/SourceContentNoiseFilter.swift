import Foundation
import BrowseCraftCore

enum SourceContentNoiseContext: String, Hashable {
    case listItem
    case navigationLink
    case playbackCandidate
    case feedItem
    case chapterLink
}

enum SourceContentNoiseAction: String, Hashable {
    case keep
    case discard
    case deprioritize
}

enum SourceContentNoiseReason: String, Hashable {
    case emptyContent
    case advertising
    case popupOrOverlay
    case tracking
    case accountNavigation
    case externalPromotion
}

struct SourceContentNoiseCandidate: Hashable {
    var title: String?
    var url: URL?
    var text: String?
    var cssClass: String?
    var elementID: String?
    var tagName: String?
    var attributes: [String: String]
    var sourceKind: SourceRuntimeKind?
    var context: SourceContentNoiseContext

    init(
        title: String? = nil,
        url: URL? = nil,
        text: String? = nil,
        cssClass: String? = nil,
        elementID: String? = nil,
        tagName: String? = nil,
        attributes: [String: String] = [:],
        sourceKind: SourceRuntimeKind? = nil,
        context: SourceContentNoiseContext
    ) {
        self.title = title
        self.url = url
        self.text = text
        self.cssClass = cssClass
        self.elementID = elementID
        self.tagName = tagName
        self.attributes = attributes
        self.sourceKind = sourceKind
        self.context = context
    }
}

struct SourceContentNoiseDecision: Hashable {
    var action: SourceContentNoiseAction
    var reasons: [SourceContentNoiseReason]

    static let keep: SourceContentNoiseDecision = SourceContentNoiseDecision(
        action: .keep,
        reasons: []
    )
}

protocol SourceContentNoiseFiltering {
    func decision(for candidate: SourceContentNoiseCandidate) -> SourceContentNoiseDecision
}

struct SourceContentNoiseFilter: SourceContentNoiseFiltering {
    private enum Markers {
        static let advertising: [String] = [
            "ads",
            "ad-",
            "-ad",
            "_ad",
            "advert",
            "advertise",
            "advertisement",
            "banner",
            "sponsor",
            "sponsored",
            "promotion",
            "promoted"
        ]

        static let popupOrOverlay: [String] = [
            "popup",
            "pop-up",
            "modal",
            "overlay",
            "interstitial"
        ]

        static let tracking: [String] = [
            "analytics",
            "tracking",
            "tracker",
            "pixel",
            "beacon",
            "statcounter",
            "doubleclick",
            "googletagmanager",
            "google-analytics"
        ]

        static let accountNavigation: [String] = [
            "login",
            "logout",
            "sign in",
            "signin",
            "signup",
            "register",
            "account",
            "profile",
            "登录",
            "登入",
            "注册",
            "註冊",
            "ログイン",
            "サインイン",
            "로그인"
        ]

        static let externalPromotion: [String] = [
            "download app",
            "install app",
            "apk",
            "app store",
            "play store",
            "telegram",
            "discord"
        ]

        static let playback: [String] = [
            "player",
            "play",
            "embed",
            "iframe",
            "video",
            "m3u8",
            "mp4"
        ]
    }

    func decision(for candidate: SourceContentNoiseCandidate) -> SourceContentNoiseDecision {
        var reasons: [SourceContentNoiseReason] = []
        let searchableText: String = self.searchableText(for: candidate)

        if self.isEmptyContent(candidate) {
            reasons.append(.emptyContent)
        }

        if self.containsMarker(in: searchableText, markers: Markers.tracking) {
            reasons.append(.tracking)
        }

        if self.containsMarker(in: searchableText, markers: Markers.popupOrOverlay) {
            reasons.append(.popupOrOverlay)
        }

        if self.containsMarker(in: searchableText, markers: Markers.advertising),
           self.hasPlaybackSignal(candidate) == false {
            reasons.append(.advertising)
        }

        if self.shouldTreatAsAccountNavigation(candidate, searchableText: searchableText) {
            reasons.append(.accountNavigation)
        }

        if self.containsMarker(in: searchableText, markers: Markers.externalPromotion),
           self.hasPlaybackSignal(candidate) == false {
            reasons.append(.externalPromotion)
        }

        guard reasons.isEmpty == false else {
            return .keep
        }

        return SourceContentNoiseDecision(
            action: .discard,
            reasons: Array(Set(reasons)).sorted { $0.rawValue < $1.rawValue }
        )
    }

    private func isEmptyContent(_ candidate: SourceContentNoiseCandidate) -> Bool {
        switch candidate.context {
        case .listItem, .feedItem, .chapterLink:
            return self.isBlank(candidate.title)
                && candidate.url == nil
                && self.isBlank(candidate.text)
        case .navigationLink, .playbackCandidate:
            return candidate.url == nil && self.isBlank(candidate.title)
        }
    }

    private func shouldTreatAsAccountNavigation(
        _ candidate: SourceContentNoiseCandidate,
        searchableText: String
    ) -> Bool {
        guard self.containsMarker(in: searchableText, markers: Markers.accountNavigation) else {
            return false
        }

        switch candidate.context {
        case .listItem, .navigationLink, .feedItem, .chapterLink:
            return self.hasPlaybackSignal(candidate) == false
        case .playbackCandidate:
            return candidate.url?.path.lowercased().contains("login") == true
        }
    }

    private func hasPlaybackSignal(_ candidate: SourceContentNoiseCandidate) -> Bool {
        let urlText: String?
        switch candidate.context {
        case .playbackCandidate:
            urlText = candidate.url?.absoluteString
        case .listItem, .navigationLink, .feedItem, .chapterLink:
            urlText = candidate.url?.path
        }

        return self.containsMarker(
            in: [
                candidate.title,
                urlText,
                candidate.cssClass,
                candidate.elementID,
                candidate.tagName,
                candidate.attributes.values.joined(separator: " ")
            ]
                .compactMap { $0 }
                .joined(separator: " "),
            markers: Markers.playback
        )
    }

    private func searchableText(for candidate: SourceContentNoiseCandidate) -> String {
        return [
            candidate.title,
            candidate.url?.absoluteString,
            candidate.text,
            candidate.cssClass,
            candidate.elementID,
            candidate.tagName,
            candidate.attributes.keys.joined(separator: " "),
            candidate.attributes.values.joined(separator: " ")
        ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
    }

    private func containsMarker(in text: String, markers: [String]) -> Bool {
        let normalizedText: String = text.lowercased()
        return markers.contains { marker in
            normalizedText.contains(marker.lowercased())
        }
    }

    private func isBlank(_ value: String?) -> Bool {
        return value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }
}
