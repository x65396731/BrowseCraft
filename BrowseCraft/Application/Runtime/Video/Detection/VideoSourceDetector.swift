import Foundation
import BrowseCraftCore

struct VideoSourceDetector: VideoSourceDetecting {
    private let lexicon: VideoDetectionLexicon

    init(lexicon: VideoDetectionLexicon = .default) {
        self.lexicon = lexicon
    }

    func detect(_ input: VideoSourceDetectionInput) -> VideoSourceDetection {
        let signals: VideoSourceSignals = VideoSourceSignals(input: input)
        let restriction: RestrictionSignal = self.restrictionSignal(signals)
        let contentSignals: DetectionScore = self.videoContentScore(signals)
        let renderMode: VideoRenderRequirement = self.renderMode(signals)
        let playback: PlaybackDetection = self.playbackDetection(signals)
        let detectionScope: DetectionScope = self.detectionScope(
            contentSignals: contentSignals,
            restriction: restriction,
            renderMode: renderMode
        )
        let confidence: Double = self.confidence(
            signalScore: detectionScope.score,
            renderMode: renderMode,
            playbackMode: playback.mode,
            restriction: restriction
        )
        let warnings: [String] = self.warnings(
            signals: signals,
            renderMode: renderMode,
            restriction: restriction
        )

        return VideoSourceDetection(
            renderMode: renderMode,
            playbackMode: playback.mode,
            requiresPlugin: restriction.shouldUsePlugin,
            confidence: confidence,
            reasons: detectionScope.reasons + playback.reasons,
            warnings: warnings
        )
    }

    private func detectionScope(
        contentSignals: DetectionScore,
        restriction: RestrictionSignal,
        renderMode: VideoRenderRequirement
    ) -> DetectionScope {
        if restriction.shouldUsePlugin {
            return DetectionScope(
                score: restriction.score,
                reasons: restriction.reasons
            )
        }

        if renderMode == .webViewRequired {
            return DetectionScope(
                score: max(0.48, contentSignals.score),
                reasons: contentSignals.reasons + [
                    "HTML looks JavaScript-rendered; the V2 rule must declare WebView acquisition."
                ]
            )
        }

        if contentSignals.hasStructuredCMSMarkers {
            return DetectionScope(
                score: contentSignals.score,
                reasons: contentSignals.reasons + [
                    "Strong video CMS markers matched; the V2 rule still owns all selectors and routes."
                ]
            )
        }

        if contentSignals.score > 0 {
            return DetectionScope(
                score: contentSignals.score,
                reasons: contentSignals.reasons + [
                    "Video content markers matched; extraction remains V2 rule-driven."
                ]
            )
        }

        return DetectionScope(
            score: 0.30,
            reasons: ["No video content signals matched; extraction remains V2 rule-driven."]
        )
    }

    private func videoContentScore(_ signals: VideoSourceSignals) -> DetectionScore {
        var score: Double = 0
        var reasons: [String] = []

        if signals.pathMatches(#"^/vod(type|show|detail|play)/"#) {
            score += 0.76
            reasons.append("URL path matches common video CMS routes.")
        }

        let payloadMarkers: [String] = self.lexicon.markers(for: .macCMSPayload)
        let payloadMatches: [String] = signals.containedMarkers(payloadMarkers)
        if payloadMatches.isEmpty == false {
            score += 0.62
            reasons.append("HTML contains known video CMS player payload markers: \(payloadMatches.joined(separator: ", ")).")
        }

        let routeMarkers: [String] = self.lexicon.markers(for: .macCMSRoute)
        let routeMatches: [String] = signals.containedMarkers(routeMarkers)
        if routeMatches.isEmpty == false {
            score += min(0.40, Double(routeMatches.count) * 0.16)
            reasons.append("HTML contains known video CMS route markers: \(routeMatches.joined(separator: ", ")).")
        }

        let templateMarkers: [String] = self.lexicon.markers(for: .macCMSTemplate)
        let templateMatches: [String] = signals.containedMarkers(templateMarkers)
        if templateMatches.isEmpty == false {
            score += min(0.44, Double(templateMatches.count) * 0.12)
            reasons.append("HTML contains known MacCMS/vfed template markers: \(templateMatches.joined(separator: ", ")).")
        }

        let weakCMSMarkers: [String] = self.lexicon.markers(for: .macCMSWeak)
        let weakCMSMatches: [String] = signals.containedMarkers(weakCMSMarkers)
        if weakCMSMatches.count >= 2 {
            score += 0.20
            reasons.append("HTML contains multiple weak video CMS markers: \(weakCMSMatches.joined(separator: ", ")).")
        }

        let strongMarkers: [String] = self.lexicon.markers(for: .directMedia)
        let strongMatches: [String] = signals.containedMarkers(strongMarkers)
        if strongMatches.isEmpty == false {
            score += min(0.70, 0.42 + Double(strongMatches.count - 1) * 0.10)
            reasons.append("HTML contains direct video media markers: \(strongMatches.joined(separator: ", ")).")
        }

        let routeScore: Double = min(0.30, Double(signals.videoRouteHitCount) * 0.08)
        if routeScore > 0 {
            score += routeScore
            reasons.append("HTML contains repeated generic video route links.")
        }

        let mediumMarkers: [String] = self.lexicon.markers(for: .genericListCard)
        let mediumMatches: [String] = signals.containedMarkers(mediumMarkers)
        if mediumMatches.count >= 2 {
            score += min(0.28, Double(mediumMatches.count) * 0.07)
            reasons.append("HTML contains generic video card/list markers: \(mediumMatches.joined(separator: ", ")).")
        }

        let supportingMarkers: [String] = self.lexicon.markers(for: .genericSupporting)
        let supportingMatches: [String] = signals.containedMarkers(supportingMarkers)
        if supportingMatches.count >= 2 && (score > 0 || signals.videoRouteHitCount > 0) {
            score += min(0.12, Double(supportingMatches.count) * 0.03)
            reasons.append("HTML contains supporting weak video markers: \(supportingMatches.joined(separator: ", ")).")
        }

        let hasStructuredCMSMarkers: Bool = self.hasStructuredCMSMarkers(
            payloadMatches: payloadMatches,
            routeMatches: routeMatches,
            templateMatches: templateMatches
        )

        return DetectionScore(
            score: min(score, 1.0),
            reasons: reasons,
            hasStructuredCMSMarkers: hasStructuredCMSMarkers
        )
    }

    private func hasStructuredCMSMarkers(
        payloadMatches: [String],
        routeMatches: [String],
        templateMatches: [String]
    ) -> Bool {
        if templateMatches.count >= 2 {
            return true
        }

        if payloadMatches.isEmpty == false && routeMatches.isEmpty == false {
            return true
        }

        let normalizedRoutes: Set<String> = Set(routeMatches.map { $0.lowercased() })
        if normalizedRoutes.contains("/voddetail/") && normalizedRoutes.contains("/vodplay/") {
            return true
        }

        return false
    }

    private func renderMode(_ signals: VideoSourceSignals) -> VideoRenderRequirement {
        if signals.htmlIsEmptyShell
            || signals.hasUnmappedWebViewShell {
            return .webViewRequired
        }

        return .staticHTML
    }

    private func playbackDetection(_ signals: VideoSourceSignals) -> PlaybackDetection {
        let directMarkers: [String] = self.lexicon.markers(for: .directMedia)
        let directMatches: [String] = signals.containedMarkers(directMarkers)
        if directMatches.isEmpty == false {
            return PlaybackDetection(
                mode: .directMedia,
                reasons: ["Playback layer contains direct media markers: \(directMatches.joined(separator: ", "))."]
            )
        }

        let iframeMarkers: [String] = self.lexicon.markers(for: .iframePlayerPlayback)
        let iframeMatches: [String] = signals.containedMarkers(iframeMarkers)
        if signals.hasIframeElement && iframeMatches.isEmpty == false {
            return PlaybackDetection(
                mode: .iframePlayer,
                reasons: ["Playback layer contains iframe/embed markers: \(iframeMatches.joined(separator: ", "))."]
            )
        }

        return PlaybackDetection(mode: .unresolved, reasons: [])
    }

    private func restrictionSignal(_ signals: VideoSourceSignals) -> RestrictionSignal {
        let pluginMarkers: [String] = self.lexicon.markers(for: .pluginRestriction)
        let matches: [String] = signals.containedMarkers(pluginMarkers)
        guard matches.isEmpty == false else {
            return RestrictionSignal(
                score: 0,
                shouldUsePlugin: false,
                reasons: []
            )
        }

        return RestrictionSignal(
            score: matches.count >= 2 ? 0.88 : 0.78,
            shouldUsePlugin: true,
            reasons: ["HTML contains plugin-level markers: \(matches.joined(separator: ", "))."]
        )
    }

    private func warnings(
        signals: VideoSourceSignals,
        renderMode: VideoRenderRequirement,
        restriction: RestrictionSignal
    ) -> [String] {
        var warnings: [String] = []

        if renderMode == .webViewRequired {
            warnings.append("Static HTML may not contain final list, detail, or playback data.")
        }

        if restriction.shouldUsePlugin {
            warnings.append("This source may need account, CAPTCHA, signing, or decryption support.")
        }

        if signals.containsAny(self.lexicon.markers(for: .payRestriction)) {
            warnings.append("The page contains VIP/member restriction markers.")
        }

        if signals.containsAny(self.lexicon.markers(for: .accountRestriction)) {
            warnings.append("The page contains login markers.")
        }

        return warnings
    }

    private func confidence(
        signalScore: Double,
        renderMode: VideoRenderRequirement,
        playbackMode: VideoPlaybackMode,
        restriction: RestrictionSignal
    ) -> Double {
        if restriction.shouldUsePlugin {
            return restriction.score
        }

        var confidence: Double = signalScore
        if renderMode == .webViewRequired {
            confidence = min(1.0, confidence + 0.05)
        }

        if playbackMode != .unresolved {
            confidence = min(1.0, confidence + 0.06)
        }

        return min(max(confidence, 0.30), 0.98)
    }
}

private struct DetectionScope {
    var score: Double
    var reasons: [String]
}

private struct DetectionScore {
    var score: Double
    var reasons: [String]
    var hasStructuredCMSMarkers: Bool
}

private struct PlaybackDetection {
    var mode: VideoPlaybackMode
    var reasons: [String]
}

private struct RestrictionSignal {
    var score: Double
    var shouldUsePlugin: Bool
    var reasons: [String]
}

private struct VideoSourceSignals {
    let path: String
    let html: String
    let haystack: String

    init(input: VideoSourceDetectionInput) {
        self.path = input.url.path.lowercased()
        self.html = (input.html ?? "").lowercased()
        let headerText: String = input.headers
            .map { key, value in "\(key): \(value)" }
            .joined(separator: "\n")
        self.haystack = [
            input.url.absoluteString,
            input.html ?? "",
            headerText
        ]
        .joined(separator: "\n")
        .lowercased()
    }

    var htmlIsEmptyShell: Bool {
        let trimmed: String = self.html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return false
        }

        return self.hasAppShell && self.hasMappableVideoContent == false
    }

    var hasUnmappedWebViewShell: Bool {
        return self.hasAppShell && self.hasMappableVideoContent == false
    }

    private var hasAppShell: Bool {
        return self.htmlContainsAny(VideoDetectionLexicon.default.markers(for: .webViewShell))
    }

    private var hasMappableVideoContent: Bool {
        return self.htmlContainsAny([
            "/voddetail/",
            "/vodplay/",
            "/watch",
            "/video",
            "/videos/",
            ".m3u8",
            ".mp4",
            "<video",
            "video-card",
            "video-item",
            "thumbnail"
        ]) || self.hasPlaybackIframeSignal
    }

    var videoRouteHitCount: Int {
        let patterns: [String] = [
            #"/video"#,
            #"/watch"#,
            #"/play"#,
            #"href=[\"'][^\"']*(video|watch|play)"#
        ]

        return patterns.reduce(0) { partialResult, pattern in
            partialResult + self.matchCount(pattern)
        }
    }

    var hasIframeElement: Bool {
        return self.contains("<iframe") || self.contains("iframe src=")
    }

    var hasPlaybackIframeSignal: Bool {
        return self.hasIframeElement && self.containsAny(VideoDetectionLexicon.default.markers(for: .iframePlayerPlayback))
    }

    func contains(_ marker: String) -> Bool {
        return self.haystack.contains(marker.lowercased())
    }

    func containsAny(_ markers: [String]) -> Bool {
        return self.containedMarkers(markers).isEmpty == false
    }

    func htmlContainsAny(_ markers: [String]) -> Bool {
        return markers.contains { marker in
            self.html.contains(marker.lowercased())
        }
    }

    func containedMarkers(_ markers: [String]) -> [String] {
        return markers.filter { marker in
            self.contains(marker)
        }
    }

    func pathMatches(_ pattern: String) -> Bool {
        return self.path.range(of: pattern, options: .regularExpression) != nil
    }

    private func matchCount(_ pattern: String) -> Int {
        guard let regex: NSRegularExpression = try? NSRegularExpression(pattern: pattern) else {
            return 0
        }

        let range: NSRange = NSRange(self.haystack.startIndex..<self.haystack.endIndex, in: self.haystack)
        return regex.numberOfMatches(in: self.haystack, range: range)
    }
}
