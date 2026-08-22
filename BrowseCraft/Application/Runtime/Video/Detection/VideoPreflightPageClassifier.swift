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

        let antiBotMarkers: [String] = [
            "cf-chl-", "cloudflare challenge", "just a moment",
            "captcha", "verify you are human", "access denied"
        ]
        if antiBotMarkers.filter({ normalized.contains($0) }).count >= 2
            || normalized.contains("cf-chl-") {
            return .antiBotChallenge
        }

        let hasPasswordField: Bool = normalized.contains("type=\"password\"")
            || normalized.contains("type='password'")
        let sessionMarkers: [String] = ["sign in", "log in", "login", "登录", "登入"]
        if hasPasswordField && sessionMarkers.contains(where: { marker in
            normalized.contains(marker)
        }) {
            return .requiresUserSession
        }

        let bodyTextEstimate: String = normalized
            .replacingOccurrences(of: #"<script[\s\S]*?</script>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"<style[\s\S]*?</style>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        let scriptCount: Int = normalized.components(separatedBy: "<script").count - 1
        let anchorCount: Int = normalized.components(separatedBy: "<a ").count - 1
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
