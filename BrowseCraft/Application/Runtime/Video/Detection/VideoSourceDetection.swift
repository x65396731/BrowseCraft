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

// Detector-only lexicon for semantic page signals. This is not a UI localization layer.
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

    var markersByCategory: [Category: [String]]

    static let `default`: VideoDetectionLexicon = VideoDetectionLexicon(
        markersByCategory: [
            .webViewShell: [
                "id=\"app\"",
                "id='app'",
                "data-reactroot",
                "__nuxt",
                "__next"
            ],
            .directMedia: [
                ".m3u8",
                ".mp4",
                "<video",
                "<source",
                "application/vnd.apple.mpegurl",
                "video/mp4"
            ],
            .macCMSPayload: [
                "player_aaaa",
                "mac_url",
                "mac_player",
                "macplayer"
            ],
            .macCMSRoute: [
                "/vodtype/",
                "/vodshow/",
                "/voddetail/",
                "/vodplay/"
            ],
            .macCMSWeak: [
                "mac_history",
                "vod_name",
                "vod_id",
                "zanpian"
            ],
            .genericListCard: [
                "video-card",
                "video-item",
                "frame-block",
                "thumb-block",
                "duration",
                "views",
                "thumbnail",
                "thumb"
            ],
            .genericSupporting: [
                "data-src",
                "lazyload",
                "playlist",
                "episode",
                "episodio",
                "エピソード",
                "에피소드",
                "播放",
                "再生",
                "재생",
                "reproducir"
            ],
            .iframePlayback: [
                "embed/",
                "/embed",
                "player",
                "allowfullscreen",
                "html5player"
            ],
            .pluginRestriction: [
                "captcha",
                "验证码",
                "認証コード",
                "캡차",
                "anti-bot",
                "cryptojs",
                "decrypt",
                "encrypted",
                "eval(function(p,a,c,k,e,d)",
                "signature",
                "wasm"
            ],
            .captchaRestriction: [
                "captcha",
                "验证码",
                "認証コード",
                "캡차",
                "anti-bot"
            ],
            .signingRestriction: [
                "signature",
                "token"
            ],
            .encryptedPlaybackRestriction: [
                "cryptojs",
                "decrypt",
                "encrypted"
            ],
            .wasmRestriction: [
                "wasm"
            ],
            .sessionRestriction: [
                "session",
                "cookie"
            ],
            .privateAPIRestriction: [
                "private api",
                "privateapi"
            ],
            .payRestriction: [
                "vip",
                "premium",
                "member-only",
                "members only",
                "会员",
                "會員",
                "付费",
                "有料",
                "会員",
                "프리미엄",
                "miembros",
                "suscriptores"
            ],
            .accountRestriction: [
                "login",
                "sign in",
                "account",
                "登录",
                "登入",
                "ログイン",
                "サインイン",
                "로그인",
                "iniciar sesión",
                "iniciar sesion"
            ],
            .navigationReject: [
                "login",
                "logout",
                "account",
                "profile",
                "history",
                "favorite",
                "favourite",
                "upload",
                "advert",
                "ads",
                "privacy",
                "terms",
                "contact",
                "support",
                "signup",
                "register",
                "会员",
                "會員",
                "登录",
                "登入",
                "注册",
                "註冊",
                "ログイン",
                "サインイン",
                "로그인"
            ]
        ]
    )

    func markers(for category: Category) -> [String] {
        return self.markersByCategory[category] ?? []
    }

    func containsMarker(in text: String, category: Category) -> Bool {
        let normalizedText: String = text.lowercased()
        return self.markers(for: category).contains { marker in
            normalizedText.contains(marker.lowercased())
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

        let lexicon: VideoDetectionLexicon = .default

        if lexicon.containsMarker(in: reasonText, category: .captchaRestriction) {
            return .captchaOrAntiBot
        }

        if lexicon.containsMarker(in: reasonText, category: .signingRestriction) {
            return .signingRequired
        }

        if lexicon.containsMarker(in: reasonText, category: .encryptedPlaybackRestriction) {
            return .encryptedPlayback
        }

        if lexicon.containsMarker(in: reasonText, category: .wasmRestriction) {
            return .wasmRequired
        }

        if lexicon.containsMarker(in: reasonText, category: .sessionRestriction)
            || lexicon.containsMarker(in: warningText, category: .accountRestriction) {
            return .sessionFlowRequired
        }

        if lexicon.containsMarker(in: reasonText, category: .privateAPIRestriction) {
            return .privateAPIRequired
        }

        return .privateAPIRequired
    }
}
