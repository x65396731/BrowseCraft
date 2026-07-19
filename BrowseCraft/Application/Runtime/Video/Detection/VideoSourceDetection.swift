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
    var renderMode: VideoRenderRequirement
    var playbackMode: VideoPlaybackMode
    var requiresPlugin: Bool
    var confidence: Double
    var reasons: [String]
    var warnings: [String]
}

enum VideoPlaybackMode: String, Codable, Hashable {
    case directMedia
    case iframePlayer
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
