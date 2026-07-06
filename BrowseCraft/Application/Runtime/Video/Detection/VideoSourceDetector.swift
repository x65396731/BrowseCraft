import Foundation
import BrowseCraftCore

struct VideoSourceDetector: VideoSourceDetecting {
    func detect(_ input: VideoSourceDetectionInput) -> VideoSourceDetection {
        let signals: VideoSourceSignals = VideoSourceSignals(input: input)
        let restriction: RestrictionSignal = self.restrictionSignal(signals)
        let macCMS: DetectionScore = self.macCMSScore(signals)
        let genericHTML: DetectionScore = self.genericHTMLScore(signals)
        let iframeContent: DetectionScore = self.iframeContentScore(signals)
        let renderMode: VideoRenderMode = self.renderMode(signals)
        let playback: PlaybackDetection = self.playbackDetection(signals)
        let adapterScore: AdapterDetection = self.adapterDetection(
            macCMS: macCMS,
            genericHTML: genericHTML,
            iframeContent: iframeContent,
            restriction: restriction,
            renderMode: renderMode
        )
        let confidence: Double = self.confidence(
            adapterScore: adapterScore.score,
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
            adapter: adapterScore.adapter,
            renderMode: renderMode,
            playbackMode: playback.mode,
            confidence: confidence,
            reasons: adapterScore.reasons + playback.reasons,
            warnings: warnings
        )
    }

    private func adapterDetection(
        macCMS: DetectionScore,
        genericHTML: DetectionScore,
        iframeContent: DetectionScore,
        restriction: RestrictionSignal,
        renderMode: VideoRenderMode
    ) -> AdapterDetection {
        if restriction.shouldUsePlugin {
            return AdapterDetection(
                adapter: .plugin,
                score: restriction.score,
                reasons: restriction.reasons
            )
        }

        if macCMS.score >= 0.72 && macCMS.score >= genericHTML.score {
            return AdapterDetection(
                adapter: .macCMS,
                score: macCMS.score,
                reasons: macCMS.reasons
            )
        }

        if iframeContent.score >= 0.62 && iframeContent.score >= genericHTML.score {
            return AdapterDetection(
                adapter: .iframe,
                score: iframeContent.score,
                reasons: iframeContent.reasons
            )
        }

        if genericHTML.score >= 0.50 {
            return AdapterDetection(
                adapter: .genericHTML,
                score: genericHTML.score,
                reasons: genericHTML.reasons
            )
        }

        if renderMode == .webViewRequired {
            return AdapterDetection(
                adapter: .genericHTML,
                score: 0.48,
                reasons: ["HTML looks JavaScript-rendered; defaulting content extraction adapter to generic HTML."]
            )
        }

        return AdapterDetection(
            adapter: .genericHTML,
            score: 0.30,
            reasons: ["No strong video content adapter signal matched; defaulting to generic HTML."]
        )
    }

    private func macCMSScore(_ signals: VideoSourceSignals) -> DetectionScore {
        var score: Double = 0
        var reasons: [String] = []

        if signals.pathMatches(#"^/vod(type|show|detail|play)/"#) {
            score += 0.82
            reasons.append("URL path matches common MacCMS routes.")
        }

        let payloadMarkers: [String] = [
            "player_aaaa",
            "mac_url",
            "mac_player",
            "macplayer"
        ]
        let payloadMatches: [String] = signals.containedMarkers(payloadMarkers)
        if payloadMatches.isEmpty == false {
            score += 0.72
            reasons.append("HTML contains MacCMS player payload markers: \(payloadMatches.joined(separator: ", ")).")
        }

        let routeMarkers: [String] = [
            "/vodtype/",
            "/vodshow/",
            "/voddetail/",
            "/vodplay/"
        ]
        let routeMatches: [String] = signals.containedMarkers(routeMarkers)
        if routeMatches.isEmpty == false {
            score += min(0.40, Double(routeMatches.count) * 0.16)
            reasons.append("HTML contains MacCMS route markers: \(routeMatches.joined(separator: ", ")).")
        }

        let weakMarkers: [String] = [
            "mac_history",
            "vod_name",
            "vod_id",
            "zanpian"
        ]
        let weakMatches: [String] = signals.containedMarkers(weakMarkers)
        if weakMatches.count >= 2 {
            score += 0.20
            reasons.append("HTML contains multiple MacCMS weak markers: \(weakMatches.joined(separator: ", ")).")
        }

        return DetectionScore(score: min(score, 1.0), reasons: reasons)
    }

    private func genericHTMLScore(_ signals: VideoSourceSignals) -> DetectionScore {
        var score: Double = 0
        var reasons: [String] = []

        let strongMarkers: [String] = [
            ".m3u8",
            ".mp4",
            "<video",
            "<source"
        ]
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

        let mediumMarkers: [String] = [
            "video-card",
            "video-item",
            "frame-block",
            "thumb-block",
            "duration",
            "views",
            "thumbnail",
            "thumb"
        ]
        let mediumMatches: [String] = signals.containedMarkers(mediumMarkers)
        if mediumMatches.count >= 2 {
            score += min(0.28, Double(mediumMatches.count) * 0.07)
            reasons.append("HTML contains generic video card/list markers: \(mediumMatches.joined(separator: ", ")).")
        }

        let weakMarkers: [String] = [
            "data-src",
            "lazyload",
            "playlist",
            "episode",
            "播放"
        ]
        let weakMatches: [String] = signals.containedMarkers(weakMarkers)
        if weakMatches.count >= 2 && (score > 0 || signals.videoRouteHitCount > 0) {
            score += min(0.12, Double(weakMatches.count) * 0.03)
            reasons.append("HTML contains supporting weak video markers: \(weakMatches.joined(separator: ", ")).")
        }

        return DetectionScore(score: min(score, 1.0), reasons: reasons)
    }

    private func iframeContentScore(_ signals: VideoSourceSignals) -> DetectionScore {
        var score: Double = 0
        var reasons: [String] = []

        let frameShellMarkers: [String] = [
            "<frameset",
            "<frame "
        ]
        let frameShellMatches: [String] = signals.containedMarkers(frameShellMarkers)
        if frameShellMatches.isEmpty == false {
            score += 0.78
            reasons.append("HTML contains frame shell markers for content extraction: \(frameShellMatches.joined(separator: ", ")).")
        }

        if signals.hasIframeElement && signals.hasPlaybackIframeSignal == false {
            score += 0.64
            reasons.append("HTML contains iframe shell markers without playback/embed context.")
        }

        return DetectionScore(score: min(score, 1.0), reasons: reasons)
    }

    private func renderMode(_ signals: VideoSourceSignals) -> VideoRenderMode {
        if signals.htmlIsEmptyShell
            || signals.containsAny(["id=\"app\"", "id='app'", "data-reactroot", "__nuxt", "__next"]) {
            return .webViewRequired
        }

        return .staticHTML
    }

    private func playbackDetection(_ signals: VideoSourceSignals) -> PlaybackDetection {
        let directMarkers: [String] = [
            ".m3u8",
            ".mp4",
            "<video",
            "<source"
        ]
        let directMatches: [String] = signals.containedMarkers(directMarkers)
        if directMatches.isEmpty == false {
            return PlaybackDetection(
                mode: .directMedia,
                reasons: ["Playback layer contains direct media markers: \(directMatches.joined(separator: ", "))."]
            )
        }

        let iframeMarkers: [String] = [
            "embed/",
            "/embed",
            "player",
            "allowfullscreen",
            "html5player"
        ]
        let iframeMatches: [String] = signals.containedMarkers(iframeMarkers)
        if signals.hasIframeElement && iframeMatches.isEmpty == false {
            return PlaybackDetection(
                mode: .iframe,
                reasons: ["Playback layer contains iframe/embed markers: \(iframeMatches.joined(separator: ", "))."]
            )
        }

        return PlaybackDetection(mode: .unresolved, reasons: [])
    }

    private func restrictionSignal(_ signals: VideoSourceSignals) -> RestrictionSignal {
        let pluginMarkers: [String] = [
            "captcha",
            "验证码",
            "cryptojs",
            "decrypt",
            "encrypted",
            "eval(function(p,a,c,k,e,d)",
            "signature",
            "wasm"
        ]
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
        renderMode: VideoRenderMode,
        restriction: RestrictionSignal
    ) -> [String] {
        var warnings: [String] = []

        if renderMode == .webViewRequired {
            warnings.append("Static HTML may not contain final list, detail, or playback data.")
        }

        if restriction.shouldUsePlugin {
            warnings.append("This source may need account, CAPTCHA, signing, or decryption support.")
        }

        if signals.containsAny(["vip", "会员", "付费"]) {
            warnings.append("The page contains VIP/member restriction markers.")
        }

        if signals.containsAny(["login", "登录"]) {
            warnings.append("The page contains login markers.")
        }

        return warnings
    }

    private func confidence(
        adapterScore: Double,
        renderMode: VideoRenderMode,
        playbackMode: VideoPlaybackMode,
        restriction: RestrictionSignal
    ) -> Double {
        if restriction.shouldUsePlugin {
            return restriction.score
        }

        var confidence: Double = adapterScore
        if renderMode == .webViewRequired {
            confidence = min(1.0, confidence + 0.05)
        }

        if playbackMode != .unresolved {
            confidence = min(1.0, confidence + 0.06)
        }

        return min(max(confidence, 0.30), 0.98)
    }
}

private struct AdapterDetection {
    var adapter: VideoAdapter
    var score: Double
    var reasons: [String]
}

private struct DetectionScore {
    var score: Double
    var reasons: [String]
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
    let haystack: String

    init(input: VideoSourceDetectionInput) {
        self.path = input.url.path.lowercased()
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
        let trimmed: String = self.haystack.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return false
        }

        let hasAppShell: Bool = self.containsAny(["id=\"app\"", "id='app'", "__nuxt", "__next"])
        let hasVideoContent: Bool = self.containsAny([
            "/voddetail/",
            "/vodplay/",
            "/watch",
            "/video",
            ".m3u8",
            ".mp4",
            "<video"
        ]) || self.hasPlaybackIframeSignal

        return hasAppShell && hasVideoContent == false
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
        return self.hasIframeElement && self.containsAny([
            "embed/",
            "/embed",
            "player",
            "allowfullscreen",
            "html5player"
        ])
    }

    func contains(_ marker: String) -> Bool {
        return self.haystack.contains(marker.lowercased())
    }

    func containsAny(_ markers: [String]) -> Bool {
        return self.containedMarkers(markers).isEmpty == false
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
