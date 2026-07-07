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

// Video-specific facade over the shared source detection lexicon. This is not a UI localization layer.
struct VideoDetectionLexicon: Hashable {
    enum Category: Hashable {
        case webViewShell
        case directMedia
        case macCMSPayload
        case macCMSRoute
        case macCMSWeak
        case genericListCard
        case genericSupporting
        case iframePlayback
        case pluginRestriction
        case captchaRestriction
        case signingRestriction
        case encryptedPlaybackRestriction
        case wasmRestriction
        case sessionRestriction
        case privateAPIRestriction
        case payRestriction
        case accountRestriction
        case navigationReject
    }

    private let sourceLexicon: SourceDetectionLexicon

    static let `default`: VideoDetectionLexicon = VideoDetectionLexicon()

    init(sourceLexicon: SourceDetectionLexicon = .default) {
        self.sourceLexicon = sourceLexicon
    }

    func markers(for category: Category) -> [String] {
        return self.sourceLexicon.markers(for: category.sourceCategory)
    }

    func containsMarker(in text: String, category: Category) -> Bool {
        return self.sourceLexicon.containsMarker(in: text, category: category.sourceCategory)
    }
}

private extension VideoDetectionLexicon.Category {
    var sourceCategory: SourceDetectionLexicon.Category {
        switch self {
        case .webViewShell:
            return .webViewShell
        case .directMedia:
            return .directMedia
        case .macCMSPayload:
            return .macCMSPayload
        case .macCMSRoute:
            return .macCMSRoute
        case .macCMSWeak:
            return .macCMSWeak
        case .genericListCard:
            return .genericListCard
        case .genericSupporting:
            return .genericSupporting
        case .iframePlayback:
            return .iframePlayback
        case .pluginRestriction:
            return .pluginRestriction
        case .captchaRestriction:
            return .captchaRestriction
        case .signingRestriction:
            return .signingRestriction
        case .encryptedPlaybackRestriction:
            return .encryptedPlaybackRestriction
        case .wasmRestriction:
            return .wasmRestriction
        case .sessionRestriction:
            return .sessionRestriction
        case .privateAPIRestriction:
            return .privateAPIRestriction
        case .payRestriction:
            return .payRestriction
        case .accountRestriction:
            return .accountRestriction
        case .navigationReject:
            return .navigationReject
        }
    }
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

        if self.lexicon.containsMarker(in: reasonText, category: .sessionRestriction)
            || self.lexicon.containsMarker(in: warningText, category: .accountRestriction) {
            return .sessionFlowRequired
        }

        if self.lexicon.containsMarker(in: reasonText, category: .privateAPIRestriction) {
            return .privateAPIRequired
        }

        return .privateAPIRequired
    }
}
