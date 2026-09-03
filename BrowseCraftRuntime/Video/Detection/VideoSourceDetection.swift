import Foundation
import BrowseCraftCore

public struct VideoSourceDetectionInput: Hashable, Sendable {
    public var url: URL
    public var html: String?
    public var headers: [String: String]

    public init(url: URL, html: String? = nil, headers: [String: String] = [:]) {
        self.url = url
        self.html = html
        self.headers = headers
    }
}

public struct VideoSourceDetection: Hashable, Sendable {
    public init(
        renderMode: VideoRenderRequirement,
        playbackMode: VideoPlaybackMode,
        requiresPlugin: Bool,
        confidence: Double,
        reasons: [String],
        warnings: [String]
    ) {
        self.renderMode = renderMode
        self.playbackMode = playbackMode
        self.requiresPlugin = requiresPlugin
        self.confidence = confidence
        self.reasons = reasons
        self.warnings = warnings
    }

    public var renderMode: VideoRenderRequirement
    public var playbackMode: VideoPlaybackMode
    public var requiresPlugin: Bool
    public var confidence: Double
    public var reasons: [String]
    public var warnings: [String]
}

public enum VideoPlaybackMode: String, Codable, Hashable, Sendable {
    case directMedia
    case iframePlayer
    case unresolved
}

public protocol VideoSourceDetecting: Sendable {
    func detect(_ input: VideoSourceDetectionInput) -> VideoSourceDetection
}

// Video-specific facade over the shared source detection lexicon. This is not a UI localization layer.
public struct VideoDetectionLexicon: Hashable, Sendable {
    public enum Category: Hashable {
        case webViewShell
        case directMedia
        case macCMSPayload
        case macCMSRoute
        case macCMSTemplate
        case macCMSWeak
        case genericListCard
        case genericSupporting
        case iframePlayerPlayback
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

    public static let `default`: VideoDetectionLexicon = VideoDetectionLexicon()

    public init(sourceLexicon: SourceDetectionLexicon = .default) {
        self.sourceLexicon = sourceLexicon
    }

    public func markers(for category: Category) -> [String] {
        return self.sourceLexicon.markers(for: category.sourceCategory)
    }

    public func containsMarker(in text: String, category: Category) -> Bool {
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
        case .macCMSTemplate:
            return .macCMSTemplate
        case .macCMSWeak:
            return .macCMSWeak
        case .genericListCard:
            return .genericListCard
        case .genericSupporting:
            return .genericSupporting
        case .iframePlayerPlayback:
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
