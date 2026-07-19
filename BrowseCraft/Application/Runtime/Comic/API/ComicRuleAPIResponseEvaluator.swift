import CoreFoundation
import Foundation

/// 中文注释：纯规则求值结果只回答当前 JSON 是否允许继续进入 itemPath 与字段映射。
enum ComicRuleAPIResponseEvaluation: Equatable {
    case allowParsing
    case businessFailure(message: String)
}

/// 中文注释：显式策略存在时只执行规则声明的 JSON 业务合同；缺省策略才进入旧规则兼容判断。
struct ComicRuleAPIResponseEvaluator {
    static func evaluate(
        json: Any,
        responsePolicy: APIResponsePolicy?
    ) -> ComicRuleAPIResponseEvaluation {
        guard let responsePolicy else {
            return ComicRuleLegacyAPIResponseEvaluator.evaluate(json: json)
        }

        switch responsePolicy.mode {
        case .transportOnly:
            return .allowParsing

        case .envelope:
            if let failurePath = self.firstMatchedFailurePath(
                responsePolicy.failurePaths ?? [],
                object: json
            ) {
                let message = self.declaredMessage(
                    in: json,
                    paths: responsePolicy.messagePaths
                ) ?? "API response matched failure path \(failurePath)"
                return .businessFailure(message: message)
            }

            guard let statusPath = responsePolicy.businessStatusPath?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
                  statusPath.isEmpty == false else {
                return .allowParsing
            }
            guard let rawStatus = ComicRuleJSONResolver.firstJSONValue(at: statusPath, in: json),
                  let status = self.scalar(from: rawStatus) else {
                let message = self.declaredMessage(
                    in: json,
                    paths: responsePolicy.messagePaths
                ) ?? "API response is missing business status at \(statusPath)"
                return .businessFailure(message: message)
            }

            let successValues = responsePolicy.successValues ?? []
            guard successValues.contains(status) else {
                let statusDescription = self.description(of: status)
                let fallback = "API response rejected business status \(statusPath)=\(statusDescription)"
                let message = self.declaredMessage(
                    in: json,
                    paths: responsePolicy.messagePaths
                ).map { message in
                    return "\(message) \(statusPath)=\(statusDescription)"
                } ?? fallback
                return .businessFailure(message: message)
            }

            return .allowParsing
        }
    }

    private static func firstMatchedFailurePath(_ paths: [String], object: Any) -> String? {
        for path in paths {
            let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalizedPath.isEmpty == false else {
                continue
            }
            let values = ComicRuleJSONResolver.jsonValues(at: normalizedPath, in: object)
            if values.contains(where: self.hasFailureMeaning) {
                return normalizedPath
            }
        }
        return nil
    }

    private static func hasFailureMeaning(_ value: Any) -> Bool {
        if value is NSNull {
            return false
        }
        if let string = value as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        if let values = value as? [Any] {
            return values.isEmpty == false
        }
        if let values = value as? [String: Any] {
            return values.isEmpty == false
        }
        if let boolean = value as? Bool {
            return boolean
        }
        if let number = value as? NSNumber {
            return number.doubleValue != 0
        }
        return true
    }

    private static func declaredMessage(in object: Any, paths: [String]?) -> String? {
        for path in paths ?? [] {
            let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalizedPath.isEmpty == false else {
                continue
            }
            let messages = ComicRuleJSONResolver.jsonValues(at: normalizedPath, in: object)
                .compactMap { value in
                    return ComicRuleJSONResolver.stringValue(value)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                .filter { $0.isEmpty == false }
            if messages.isEmpty == false {
                return messages.joined(separator: "; ")
            }
        }
        return nil
    }

    private static func scalar(from value: Any) -> APIResponseScalar? {
        if let string = value as? String {
            return .string(string)
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .boolean(number.boolValue)
            }
            return .number(number.doubleValue)
        }
        return nil
    }

    private static func description(of scalar: APIResponseScalar) -> String {
        switch scalar {
        case .string(let value):
            return value
        case .number(let value):
            if value.rounded() == value {
                return String(format: "%.0f", value)
            }
            return String(value)
        case .boolean(let value):
            return String(value)
        }
    }
}

/// 中文注释：Legacy evaluator 原样保留旧规则的 errors/error/code=0 推断，迁移完成后可整体删除。
private struct ComicRuleLegacyAPIResponseEvaluator {
    static func evaluate(json: Any) -> ComicRuleAPIResponseEvaluation {
        guard let dictionary = json as? [String: Any] else {
            return .allowParsing
        }

        if let errors = dictionary["errors"] as? [Any],
           errors.isEmpty == false {
            let messages = errors.compactMap { error in
                return self.errorMessage(from: error)
            }
            if messages.isEmpty == false {
                return .businessFailure(message: messages.joined(separator: "; "))
            }
            return .businessFailure(message: "API returned errors")
        }

        if let error = dictionary["error"] {
            return .businessFailure(
                message: self.errorMessage(from: error) ?? "API returned error"
            )
        }

        if let code = ComicRuleJSONResolver.stringValue(dictionary["code"]),
           code != "0" {
            let message = ComicRuleJSONResolver.stringValue(dictionary["message"])
            var details: [String] = []
            if let message, message.isEmpty == false {
                details.append(message)
            }
            details.append("code=\(code)")
            return .businessFailure(message: details.joined(separator: " "))
        }

        return .allowParsing
    }

    private static func errorMessage(from object: Any) -> String? {
        if let message = ComicRuleJSONResolver.stringValue(object) {
            return message
        }

        guard let dictionary = object as? [String: Any] else {
            return nil
        }

        let message = ComicRuleJSONResolver.stringValue(dictionary["message"])
        let code = ComicRuleJSONResolver.stringValue(dictionary["code"])
            ?? ((dictionary["extensions"] as? [String: Any]).flatMap { extensions in
                return ComicRuleJSONResolver.stringValue(extensions["code"])
            })

        var details: [String] = []
        if let message, message.isEmpty == false {
            details.append(message)
        }
        if let code, code.isEmpty == false {
            details.append("code=\(code)")
        }

        if let extensions = dictionary["extensions"] as? [String: Any] {
            for key in ["current", "limit", "requested"] {
                if let value = ComicRuleJSONResolver.stringValue(extensions[key]) {
                    details.append("\(key)=\(value)")
                }
            }
        }

        return details.isEmpty ? nil : details.joined(separator: " ")
    }
}
