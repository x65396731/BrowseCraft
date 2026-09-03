import BrowseCraftDomain
import Foundation

enum VideoPreflightPageClassification: Equatable, Sendable {
    case usableHTML
    case technicalShell
    case antiBotChallenge
    case requiresUserSession
    case unsupportedContent
}

struct VideoPreflightPageClassifier: Sendable {
    func classify(_ page: PreflightAcquiredPage) -> VideoPreflightPageClassification {
        if let mediaType: String = page.mediaType?.lowercased(),
           mediaType.contains("html") == false,
           mediaType.contains("text/plain") == false {
            return .unsupportedContent
        }
        let html: String = self.decode(page.data, encodingName: page.textEncodingName)
        let normalized: String = html.lowercased()

        // 中文注释：挑战页判据只消费 `HTMLChallengeInterstitialDetector`（`BC-EVIDENCE-081`）。
        if HTMLChallengeInterstitialDetector.isChallengeInterstitial(html) {
            return .antiBotChallenge
        }

        let bodyTextEstimate: String = normalized
            .replacingOccurrences(of: #"<script[\s\S]*?</script>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"<style[\s\S]*?</style>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        let scriptCount: Int = normalized.components(separatedBy: "<script").count - 1
        let anchorCount: Int = normalized.components(separatedBy: "<a ").count - 1

        // 中文注释：`BC-PREFLIGHT-049`——「登录页」= 密码字段 + 登录文案，且文档没有可供结构观测的正文
        // （可见文本 < 400 字符或锚点 < 10）。带登录小组件的内容页归 usableHTML，由结构观测决定。
        let hasPasswordField: Bool = normalized.contains("type=\"password\"")
            || normalized.contains("type='password'")
        let sessionMarkers: [String] = ["sign in", "log in", "login", "登录", "登入"]
        let hasSessionMarker: Bool = sessionMarkers.contains(where: { marker in
            normalized.contains(marker)
        })
        let lacksObservableBody: Bool = bodyTextEstimate.count < 400 || anchorCount < 10
        if hasPasswordField && hasSessionMarker && lacksObservableBody {
            return .requiresUserSession
        }

        if bodyTextEstimate.count < 80 && anchorCount < 2 && scriptCount > 0 {
            return .technicalShell
        }
        return .usableHTML
    }

    private func decode(_ data: Data, encodingName: String?) -> String {
        let encoding: String.Encoding
        switch encodingName?.lowercased() {
        case "utf-16", "utf16":
            encoding = .utf16
        case "shift-jis", "shift_jis", "sjis":
            encoding = .shiftJIS
        case "iso-8859-1", "latin1":
            encoding = .isoLatin1
        default:
            encoding = .utf8
        }
        return String(data: data, encoding: encoding)
            ?? String(decoding: data, as: UTF8.self)
    }
}
