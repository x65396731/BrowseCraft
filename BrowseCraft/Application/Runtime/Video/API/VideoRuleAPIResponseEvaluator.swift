import CoreFoundation
import Foundation
import BrowseCraftCore

/// 中文注释：视频 API 业务合同只决定当前 JSON 是否允许进入 itemPath 与字段映射。
enum VideoRuleAPIResponseEvaluation: Equatable {
    case allowParsing
    case businessFailure(message: String)
}

/// 中文注释：Video V2 只执行显式 responsePolicy，不提供 legacy 状态码推断。
struct VideoRuleAPIResponseEvaluator {
    static func evaluate(
        json: Any,
        policy: APIResponsePolicy
    ) -> VideoRuleAPIResponseEvaluation {
        switch policy.mode {
        case .transportOnly:
            return .allowParsing
        case .envelope:
            if let failurePath: String = self.firstMatchedFailurePath(
                policy.failurePaths ?? [],
                object: json
            ) {
                let message: String = self.declaredMessage(
                    in: json,
                    paths: policy.messagePaths
                ) ?? "API response matched failure path \(failurePath)"
                return .businessFailure(message: message)
            }
            guard let statusPath: String = self.nonEmpty(policy.businessStatusPath) else {
                return .allowParsing
            }
            guard let status: APIResponseScalar = VideoRuleJSONResolver.responseScalar(
                VideoRuleJSONResolver.firstJSONValue(at: statusPath, in: json)
            ) else {
                let message: String = self.declaredMessage(
                    in: json,
                    paths: policy.messagePaths
                ) ?? "API response is missing business status at \(statusPath)"
                return .businessFailure(message: message)
            }
            guard (policy.successValues ?? []).contains(status) else {
                let message: String = self.declaredMessage(
                    in: json,
                    paths: policy.messagePaths
                ) ?? "API response rejected business status at \(statusPath)"
                return .businessFailure(message: message)
            }
            return .allowParsing
        }
    }

    private static func firstMatchedFailurePath(
        _ paths: [String],
        object: Any
    ) -> String? {
        for rawPath: String in paths {
            guard let path: String = self.nonEmpty(rawPath) else {
                continue
            }
            if VideoRuleJSONResolver.jsonValues(at: path, in: object).contains(where: self.hasFailureMeaning) {
                return path
            }
        }
        return nil
    }

    private static func hasFailureMeaning(_ value: Any) -> Bool {
        if value is NSNull {
            return false
        }
        if let string: String = value as? String {
            return self.nonEmpty(string) != nil
        }
        if let array: [Any] = value as? [Any] {
            return array.isEmpty == false
        }
        if let dictionary: [String: Any] = value as? [String: Any] {
            return dictionary.isEmpty == false
        }
        if let number: NSNumber = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue
            }
            return number.doubleValue != 0
        }
        return true
    }

    private static func declaredMessage(
        in object: Any,
        paths: [String]?
    ) -> String? {
        for rawPath: String in paths ?? [] {
            guard let path: String = self.nonEmpty(rawPath) else {
                continue
            }
            let messages: [String] = VideoRuleJSONResolver.jsonValues(at: path, in: object).compactMap { value in
                return self.nonEmpty(VideoRuleJSONResolver.stringValue(value))
            }
            if messages.isEmpty == false {
                return messages.joined(separator: "; ")
            }
        }
        return nil
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let normalized: String? = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized?.isEmpty == false ? normalized : nil
    }
}
