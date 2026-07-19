import Foundation
import BrowseCraftCore

// 中文注释：VideoHTMLRenderGuard 判断 HTML 是否仍需要 WebView 渲染；WebView 已渲染的 DOM 允许进入内容 mapper。
struct VideoHTMLRenderGuard {
    private let detector: any VideoSourceDetecting

    init(detector: any VideoSourceDetecting = VideoSourceDetector()) {
        self.detector = detector
    }

    func validateMappableHTML(
        url: URL,
        html: String,
        request: RequestConfig?,
        headers: [String: String] = [:]
    ) throws -> [SourceRuntimeIssue] {
        if request?.needsWebView == true {
            return try self.validateRenderedHTML(url: url, html: html, headers: headers)
        }

        let detection: VideoSourceDetection = self.detector.detect(
            VideoSourceDetectionInput(
                url: url,
                html: html,
                headers: headers
            )
        )

        guard detection.renderMode == .staticHTML else {
            throw SourceRuntimeError.unsupported(
                .custom(self.webViewRequiredMessage(detection: detection))
            )
        }

        return []
    }

    private func validateRenderedHTML(
        url: URL,
        html: String,
        headers: [String: String]
    ) throws -> [SourceRuntimeIssue] {
        guard html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw SourceRuntimeError.unsupported(
                .custom("video.renderedHTMLEmpty: WebView rendered empty HTML for \(url.absoluteString).")
            )
        }

        let detection: VideoSourceDetection = self.detector.detect(
            VideoSourceDetectionInput(
                url: url,
                html: html,
                headers: headers
            )
        )

        guard detection.renderMode == .staticHTML else {
            throw SourceRuntimeError.unsupported(
                .custom("video.renderedHTMLStillShell: WebView rendered DOM still looks like a JavaScript shell. \(self.webViewRequiredMessage(detection: detection))")
            )
        }

        var issues: [SourceRuntimeIssue] = [
            SourceRuntimeIssue(
                id: "video.webViewRenderedDOMUsed",
                severity: .info,
                message: "Video runtime used WebView-rendered DOM before content mapping."
            )
        ]

        if detection.requiresPlugin || detection.reasons.contains(where: { reason in
            return reason.localizedCaseInsensitiveContains("captcha")
                || reason.localizedCaseInsensitiveContains("anti-bot")
        }) {
            issues.append(
                SourceRuntimeIssue(
                    id: "video.blockedByAntiBot",
                    severity: .error,
                    message: "WebView-rendered DOM still appears blocked by anti-bot or captcha protection."
                )
            )
        }

        if detection.warnings.contains(where: { warning in
            return warning.localizedCaseInsensitiveContains("login")
        }) {
            issues.append(
                SourceRuntimeIssue(
                    id: "video.requiresAccount",
                    severity: .warning,
                    message: "WebView-rendered DOM contains login/account markers."
                )
            )
        }

        return issues
    }

    private func webViewRequiredMessage(detection: VideoSourceDetection) -> String {
        var details: [String] = [
            "Video source requires WebView-rendered DOM before content mapping.",
            "Render mode: \(detection.renderMode.rawValue).",
            "Content extraction is selected by the V2 rule.",
            "Playback mode: \(detection.playbackMode.rawValue)."
        ]

        if detection.warnings.isEmpty == false {
            details.append("Warnings: \(detection.warnings.joined(separator: " "))")
        }

        return details.joined(separator: " ")
    }
}
