import Foundation
import BrowseCraftCore

// 中文注释：导入决策只解释 detection 事实，不自动选择 macCMS/genericHTML mapper。
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
    case pluginBoundaryClosed
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
            return .unavailable(.pluginBoundaryClosed)
        }

        guard self.isBuiltInAdapter(definition.adapter) else {
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
        guard definition.adapter == .webView || detection.renderMode == .webViewRequired else {
            return definition
        }

        return VideoSourceDefinition(
            adapter: definition.adapter == .webView ? .genericHTML : definition.adapter,
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

    private func isBuiltInAdapter(_ adapter: VideoAdapter) -> Bool {
        switch adapter {
        case .macCMS, .genericHTML, .webView:
            return true
        case .plugin:
            return false
        }
    }

    private func hasNoVideoSignals(_ detection: VideoSourceDetection) -> Bool {
        return detection.reasons.contains { reason in
            return reason.localizedCaseInsensitiveContains("No video content signals matched")
        }
    }
}
