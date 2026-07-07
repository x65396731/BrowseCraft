import Foundation
import BrowseCraftCore

struct VideoSourceDetectionInput: Hashable {
    var url: URL
    var html: String?
    var headers: [String: String]

    init(url: URL, html: String? = nil, headers: [String: String] = [:]) {
        self.url = url
        self.html = html
        self.headers = headers
    }
}

struct VideoSourceDetection: Hashable {
    var adapter: VideoAdapter
    var renderMode: VideoRenderMode
    var playbackMode: VideoPlaybackMode
    var confidence: Double
    var reasons: [String]
    var warnings: [String]
}

enum VideoRenderMode: String, Codable, Hashable {
    case staticHTML
    case webViewRequired
}

enum VideoPlaybackMode: String, Codable, Hashable {
    case directMedia
    case iframe
    case unresolved
}

protocol VideoSourceDetecting {
    func detect(_ input: VideoSourceDetectionInput) -> VideoSourceDetection
}

// Converts detection signals into import branches for supported, unavailable, and plugin-required sources.
enum VideoSourceImportDecision: Hashable {
    case supported(VideoSourceDefinition)
    case needsReview(VideoSourceDefinition, warnings: [String])
    case unavailable(VideoSourceUnavailableReason)
    case pluginRequired(VideoSourcePluginReason)
}

enum VideoSourceUnavailableReason: String, Codable, Hashable {
    case unknownStructure
    case lowConfidence
    case noVideoSignals
    case unsupportedAdapter
    case webViewNotConnected
    case iframeContentNotConnected
}

enum VideoSourcePluginReason: String, Codable, Hashable {
    case captchaOrAntiBot
    case signingRequired
    case encryptedPlayback
    case wasmRequired
    case sessionFlowRequired
    case privateAPIRequired
}

struct VideoSourceImportDecisionResolver {
    private let supportedConfidenceThreshold: Double
    private let reviewConfidenceThreshold: Double

    init(
        supportedConfidenceThreshold: Double = 0.72,
        reviewConfidenceThreshold: Double = 0.50
    ) {
        self.supportedConfidenceThreshold = supportedConfidenceThreshold
        self.reviewConfidenceThreshold = reviewConfidenceThreshold
    }

    func decision(
        for detection: VideoSourceDetection,
        definition: VideoSourceDefinition
    ) -> VideoSourceImportDecision {
        if detection.adapter == .plugin {
            return .pluginRequired(self.pluginReason(from: detection))
        }

        if detection.renderMode == .webViewRequired || detection.adapter == .webView {
            return .unavailable(.webViewNotConnected)
        }

        if detection.adapter == .iframe {
            return .unavailable(.iframeContentNotConnected)
        }

        guard detection.adapter == .macCMS || detection.adapter == .genericHTML else {
            return .unavailable(.unsupportedAdapter)
        }

        if self.hasNoVideoSignals(detection) {
            return .unavailable(.noVideoSignals)
        }

        if detection.confidence < self.reviewConfidenceThreshold {
            return .unavailable(.lowConfidence)
        }

        if detection.confidence < self.supportedConfidenceThreshold || detection.warnings.isEmpty == false {
            return .needsReview(definition, warnings: detection.warnings)
        }

        return .supported(definition)
    }

    private func hasNoVideoSignals(_ detection: VideoSourceDetection) -> Bool {
        return detection.reasons.contains { reason in
            return reason.localizedCaseInsensitiveContains("No strong video content adapter signal")
        }
    }

    private func pluginReason(from detection: VideoSourceDetection) -> VideoSourcePluginReason {
        let reasonText: String = detection.reasons
            .joined(separator: " ")
            .lowercased()
        let warningText: String = detection.warnings
            .joined(separator: " ")
            .lowercased()

        if reasonText.contains("captcha") || reasonText.contains("验证码") || reasonText.contains("anti-bot") {
            return .captchaOrAntiBot
        }

        if reasonText.contains("signature") || reasonText.contains("token") {
            return .signingRequired
        }

        if reasonText.contains("cryptojs") || reasonText.contains("decrypt") || reasonText.contains("encrypted") {
            return .encryptedPlayback
        }

        if reasonText.contains("wasm") {
            return .wasmRequired
        }

        if reasonText.contains("session") || reasonText.contains("cookie") || warningText.contains("account") {
            return .sessionFlowRequired
        }

        if reasonText.contains("private api") || reasonText.contains("privateapi") {
            return .privateAPIRequired
        }

        return .privateAPIRequired
    }
}
