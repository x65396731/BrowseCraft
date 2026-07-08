import Foundation
import BrowseCraftCore

// 中文注释：导入决策只解释 detection 结果，不执行 mapper、WebView 或插件。
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
    private let lexicon: VideoDetectionLexicon

    init(
        supportedConfidenceThreshold: Double = 0.72,
        reviewConfidenceThreshold: Double = 0.50,
        lexicon: VideoDetectionLexicon = .default
    ) {
        self.supportedConfidenceThreshold = supportedConfidenceThreshold
        self.reviewConfidenceThreshold = reviewConfidenceThreshold
        self.lexicon = lexicon
    }

    func decision(
        for detection: VideoSourceDetection,
        definition: VideoSourceDefinition
    ) -> VideoSourceImportDecision {
        if detection.adapter == .plugin {
            return .pluginRequired(self.pluginReason(from: detection))
        }

        guard detection.adapter == .macCMS || detection.adapter == .genericHTML || detection.adapter == .webView else {
            return .unavailable(.unsupportedAdapter)
        }

        let normalizedDefinition: VideoSourceDefinition = self.normalizedDefinition(
            definition,
            detection: detection
        )

        if self.hasNoVideoSignals(detection) {
            return .unavailable(.noVideoSignals)
        }

        if detection.confidence < self.reviewConfidenceThreshold {
            return .unavailable(.lowConfidence)
        }

        if detection.renderMode == .webViewRequired {
            return .needsReview(
                normalizedDefinition,
                warnings: self.webViewWarnings(from: detection)
            )
        }

        if detection.confidence < self.supportedConfidenceThreshold || detection.warnings.isEmpty == false {
            return .needsReview(normalizedDefinition, warnings: detection.warnings)
        }

        return .supported(normalizedDefinition)
    }

    private func normalizedDefinition(
        _ definition: VideoSourceDefinition,
        detection: VideoSourceDetection
    ) -> VideoSourceDefinition {
        guard detection.adapter == .webView || detection.renderMode == .webViewRequired else {
            return definition
        }

        return VideoSourceDefinition(
            adapter: detection.adapter == .webView ? .genericHTML : definition.adapter,
            entryURL: definition.entryURL,
            seedURL: definition.seedURL,
            entryKind: definition.entryKind,
            routePatterns: definition.routePatterns,
            playbackPolicy: definition.playbackPolicy,
            sharedRequest: self.webViewRequest(definition.sharedRequest),
            listRequest: definition.listRequest,
            detailRequest: definition.detailRequest,
            playRequest: definition.playRequest,
            requiresAccount: definition.requiresAccount,
            seedVodID: definition.seedVodID,
            seedSourceIndex: definition.seedSourceIndex,
            seedEpisodeIndex: definition.seedEpisodeIndex,
            seedDetailURL: definition.seedDetailURL,
            seedPlayURL: definition.seedPlayURL
        )
    }

    private func webViewRequest(_ request: RequestConfig?) -> RequestConfig {
        return RequestConfig(
            scope: request?.scope,
            mergePolicy: request?.mergePolicy,
            method: request?.method,
            headers: request?.headers,
            body: request?.body,
            cookiePolicy: request?.cookiePolicy,
            cookiePriority: request?.cookiePriority,
            cookieScope: request?.cookieScope,
            charset: request?.charset,
            needsWebView: true,
            autoScroll: request?.autoScroll,
            imageHeaders: request?.imageHeaders,
            imageRequest: request?.imageRequest
        )
    }

    private func webViewWarnings(from detection: VideoSourceDetection) -> [String] {
        var warnings: [String] = detection.warnings
        warnings.append("This video source requires WebView-rendered DOM before content mapping.")
        return Array(Set(warnings)).sorted()
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

        if self.lexicon.containsMarker(in: reasonText, category: .captchaRestriction) {
            return .captchaOrAntiBot
        }

        if self.lexicon.containsMarker(in: reasonText, category: .signingRestriction) {
            return .signingRequired
        }

        if self.lexicon.containsMarker(in: reasonText, category: .encryptedPlaybackRestriction) {
            return .encryptedPlayback
        }

        if self.lexicon.containsMarker(in: reasonText, category: .wasmRestriction) {
            return .wasmRequired
        }

        if self.lexicon.containsMarker(in: reasonText, category: .sessionRestriction) {
            return .sessionFlowRequired
        }

        if self.lexicon.containsMarker(in: reasonText, category: .privateAPIRestriction) {
            return .privateAPIRequired
        }

        return .privateAPIRequired
    }
}
