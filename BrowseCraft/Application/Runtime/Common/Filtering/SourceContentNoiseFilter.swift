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
    case navigationReject
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
    private let lexicon: SourceDetectionLexicon

    init(lexicon: SourceDetectionLexicon = .default) {
        self.lexicon = lexicon
    }

    func decision(for candidate: SourceContentNoiseCandidate) -> SourceContentNoiseDecision {
        var reasons: [SourceContentNoiseReason] = []
        let searchableText: String = self.searchableText(for: candidate)

        if self.isEmptyContent(candidate) {
            reasons.append(.emptyContent)
        }

        if self.lexicon.containsMarker(in: searchableText, category: .tracking) {
            reasons.append(.tracking)
        }

        if self.lexicon.containsMarker(in: searchableText, category: .popupOrOverlay) {
            reasons.append(.popupOrOverlay)
        }

        if self.lexicon.containsMarker(in: searchableText, category: .advertising),
           self.hasPlaybackSignal(candidate) == false {
            reasons.append(.advertising)
        }

        if self.shouldTreatAsAccountNavigation(candidate, searchableText: searchableText) {
            reasons.append(.accountNavigation)
        }

        if self.lexicon.containsMarker(in: searchableText, category: .externalPromotion),
           self.hasPlaybackSignal(candidate) == false {
            reasons.append(.externalPromotion)
        }

        if self.shouldTreatAsRejectedNavigation(candidate, searchableText: searchableText) {
            reasons.append(.navigationReject)
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
        guard self.lexicon.containsMarker(in: searchableText, category: .accountNavigation) else {
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
            // The host may contain broad words such as "video". Treating the
            // full URL as playback evidence can hide redirect/ad paths.
            urlText = candidate.url?.path
        case .listItem, .navigationLink, .feedItem, .chapterLink:
            urlText = candidate.url?.path
        }

        return self.lexicon.containsMarker(
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
            category: .playbackStructure
        )
    }

    private func shouldTreatAsRejectedNavigation(
        _ candidate: SourceContentNoiseCandidate,
        searchableText: String
    ) -> Bool {
        guard candidate.context == .navigationLink || candidate.context == .playbackCandidate,
              self.hasPlaybackSignal(candidate) == false else {
            return false
        }

        if self.lexicon.containsMarker(in: searchableText, category: .navigationReject) {
            return true
        }

        guard let url: URL = candidate.url else {
            return false
        }

        return self.hasSuspiciousNavigationURLSignals(url)
    }

    private func hasSuspiciousNavigationURLSignals(_ url: URL) -> Bool {
        guard let components: URLComponents = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return false
        }

        let suspiciousHostTokens: Set<String> = [
            "ad",
            "ads",
            "adservice",
            "adserver",
            "analytics",
            "beacon",
            "doubleclick",
            "popup",
            "promo",
            "tracking",
            "tracker"
        ]
        let suspiciousPathTokens: Set<String> = [
            "ad",
            "ads",
            "advert",
            "advertisement",
            "banner",
            "click",
            "interstitial",
            "overlay",
            "popup",
            "promo",
            "promotion",
            "redirect",
            "sponsor",
            "sponsored",
            "track",
            "tracker",
            "tracking"
        ]
        let suspiciousQueryKeys: Set<String> = [
            "ad",
            "ads",
            "adurl",
            "aff",
            "aff_id",
            "affiliate",
            "clickid",
            "fbclid",
            "gclid",
            "msclkid",
            "redirect",
            "redirect_url",
            "ref",
            "referrer",
            "target",
            "target_url",
            "url"
        ]
        let suspiciousQueryValueTokens: Set<String> = [
            "ad",
            "ads",
            "appstore",
            "banner",
            "discord",
            "download-app",
            "interstitial",
            "overlay",
            "playstore",
            "popup",
            "promo",
            "redirect",
            "sponsor",
            "telegram",
            "track",
            "tracker"
        ]

        var score: Int = 0

        let hostHits: Int = Set(
            (components.host ?? "")
                .split(separator: ".")
                .map { self.normalizedNavigationToken(String($0)) }
                .filter { suspiciousHostTokens.contains($0) }
        ).count
        score += min(2, hostHits * 2)

        let pathHits: Int = Set(
            components.path
                .split(separator: "/")
                .map { self.normalizedNavigationToken(String($0)) }
                .filter { suspiciousPathTokens.contains($0) }
        ).count
        score += min(2, pathHits)

        let queryItems: [URLQueryItem] = components.queryItems ?? []
        let queryKeyHits: Int = queryItems.reduce(into: 0) { result, item in
            let key: String = self.normalizedNavigationToken(item.name)
            if suspiciousQueryKeys.contains(key) || key.hasPrefix("utm_") {
                result += 1
            }
        }
        score += min(2, queryKeyHits)

        let queryValueHits: Int = queryItems.reduce(into: 0) { result, item in
            let values: [String] = [
                item.value,
                item.value?.removingPercentEncoding
            ]
                .compactMap { $0 }
            for value in values {
                let normalizedValue: String = self.normalizedNavigationToken(value)
                if suspiciousQueryValueTokens.contains(normalizedValue) {
                    result += 1
                    continue
                }

                if value.lowercased().contains("app store")
                    || value.lowercased().contains("play store") {
                    result += 1
                }
            }
        }
        score += min(2, queryValueHits)

        return score >= 2
    }

    private func normalizedNavigationToken(_ value: String) -> String {
        return value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(
                of: #"[^a-z0-9_]+"#,
                with: "",
                options: .regularExpression
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

    private func isBlank(_ value: String?) -> Bool {
        return value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }
}
