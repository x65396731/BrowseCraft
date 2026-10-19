import Foundation

// 中文注释：问题报告对象网址的清洗（docs/design/Problem-Report-Design.md 第六节，`BCA-OBS-019`）。
// PortalCore `app/modules/problem_reports/sanitize.py` 用同一套规则再洗一遍；两边的表驱动测试用例逐条一致：
// - 去掉 user:pass@、查询串与片段，只留 scheme、主机（含端口）与路径；
// - 路径段命中任一条即换成 `:token`：JWT 形状（eyJ 开头且含两个点）、前一段是 token / auth / session / sign / key
//   一类的段名、长度不小于 32 且同时含大写、小写与数字的 base64url 串；
// - 只由十六进制组成、长度不超过 40 的段保留（多半是章节或图片 ID，去掉就重放不了）。

enum ProblemReportURLSanitizer {
    static let tokenPlaceholder: String = ":token"

    private static let secretSegmentNames: Set<String> = [
        "token", "tokens", "access_token", "accesstoken", "auth", "authorization",
        "session", "sessionid", "sid", "sign", "signature", "key", "apikey", "api_key"
    ]

    static func clean(_ raw: String?) -> String? {
        guard let raw: String, var components: URLComponents = URLComponents(string: raw.trimmingCharacters(in: .whitespaces)),
              let scheme: String = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host: String = components.host, host.isEmpty == false else {
            return nil
        }
        components.scheme = scheme
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        var previous: String = ""
        let segments: [String] = components.percentEncodedPath.components(separatedBy: "/").map { segment in
            let cleaned: String = Self.isSecret(segment, previous: previous) ? Self.tokenPlaceholder : segment
            if segment.isEmpty == false {
                previous = segment
            }
            return cleaned
        }
        components.percentEncodedPath = segments.joined(separator: "/")
        return components.string
    }

    private static func isSecret(_ segment: String, previous: String) -> Bool {
        guard segment.isEmpty == false else {
            return false
        }
        if segment.hasPrefix("eyJ"), segment.filter({ $0 == "." }).count >= 2 {
            return true
        }
        if Self.secretSegmentNames.contains(previous.lowercased()) {
            return true
        }
        if segment.count <= 40, segment.allSatisfy(\.isHexDigit) {
            return false
        }
        let isBase64URL: Bool = segment.allSatisfy { character in
            return character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_")
        }
        return segment.count >= 32
            && isBase64URL
            && segment.contains(where: \.isUppercase)
            && segment.contains(where: \.isLowercase)
            && segment.contains(where: \.isNumber)
    }
}
