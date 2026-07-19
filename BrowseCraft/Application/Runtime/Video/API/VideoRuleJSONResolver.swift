import CoreFoundation
import Foundation
import BrowseCraftCore

enum VideoRuleJSONPathState: String, Equatable {
    case missing
    case null
    case typeMismatch
    case empty
    case nonEmpty
}

struct VideoRuleJSONArrayResolution {
    let state: VideoRuleJSONPathState
    let values: [Any]
}

struct VideoRuleJSONObjectResolution {
    let state: VideoRuleJSONPathState
    let value: [String: Any]?
}

// 中文注释：VideoRuleJSONResolver 只处理 JSON Path、字段值、URL 规范化和规则排序。
struct VideoRuleJSONResolver {
    static func arrayResolution(
        at path: String,
        in object: Any
    ) -> VideoRuleJSONArrayResolution {
        if path == "$[]" {
            return self.rootArrayResolution(object)
        }
        if path == "$" {
            return VideoRuleJSONArrayResolution(state: .typeMismatch, values: [])
        }

        let segments: [(key: String, expandsArray: Bool)] = self.pathSegments(path)
        guard segments.isEmpty == false else {
            return VideoRuleJSONArrayResolution(state: .missing, values: [])
        }
        var values: [Any] = [object]
        var expandedArray: Bool = false

        for segment in segments {
            var nextValues: [Any] = []
            var encounteredEmptyArray: Bool = false
            for value in values {
                if value is NSNull {
                    return VideoRuleJSONArrayResolution(state: .null, values: [])
                }
                guard let dictionary: [String: Any] = value as? [String: Any] else {
                    return VideoRuleJSONArrayResolution(state: .typeMismatch, values: [])
                }
                guard let child: Any = dictionary[segment.key] else {
                    return VideoRuleJSONArrayResolution(state: .missing, values: [])
                }
                if child is NSNull {
                    return VideoRuleJSONArrayResolution(state: .null, values: [])
                }
                if segment.expandsArray {
                    guard let array: [Any] = child as? [Any] else {
                        return VideoRuleJSONArrayResolution(state: .typeMismatch, values: [])
                    }
                    expandedArray = true
                    encounteredEmptyArray = encounteredEmptyArray || array.isEmpty
                    nextValues.append(contentsOf: array)
                } else {
                    nextValues.append(child)
                }
            }
            if nextValues.isEmpty, encounteredEmptyArray {
                return VideoRuleJSONArrayResolution(state: .empty, values: [])
            }
            values = nextValues
        }

        guard expandedArray else {
            return VideoRuleJSONArrayResolution(state: .typeMismatch, values: [])
        }
        return VideoRuleJSONArrayResolution(
            state: values.isEmpty ? .empty : .nonEmpty,
            values: values
        )
    }

    static func objectResolution(
        at path: String,
        in object: Any
    ) -> VideoRuleJSONObjectResolution {
        if path == "$" {
            return self.objectResolution(value: object)
        }
        if path == "$[]" {
            return VideoRuleJSONObjectResolution(state: .typeMismatch, value: nil)
        }

        let values: [Any] = self.jsonValues(at: path, in: object)
        if values.isEmpty {
            return self.missingObjectResolution(at: path, in: object)
        }
        guard values.count == 1 else {
            return VideoRuleJSONObjectResolution(state: .typeMismatch, value: nil)
        }
        return self.objectResolution(value: values[0])
    }

    static func firstJSONValue(at path: String, in object: Any) -> Any? {
        return self.jsonValues(at: path, in: object).first
    }

    static func jsonValues(at path: String, in object: Any) -> [Any] {
        if path == "$" {
            return [object]
        }
        if path == "$[]" {
            return object as? [Any] ?? []
        }
        let segments: [(key: String, expandsArray: Bool)] = self.pathSegments(path)
        guard segments.isEmpty == false else {
            return []
        }
        return segments.reduce([object]) { values, segment in
            return values.flatMap { value -> [Any] in
                guard let dictionary: [String: Any] = value as? [String: Any],
                      let child: Any = dictionary[segment.key],
                      (child is NSNull) == false else {
                    return []
                }
                if segment.expandsArray {
                    return child as? [Any] ?? []
                }
                return [child]
            }
        }
    }

    static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }

    static func responseScalar(_ value: Any?) -> APIResponseScalar? {
        if let string: String = value as? String {
            return .string(string)
        }
        if let number: NSNumber = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .boolean(number.boolValue)
            }
            return .number(number.doubleValue)
        }
        return nil
    }

    static func absoluteHTTPURL(_ value: String?, relativeTo baseURL: URL) -> URL? {
        guard let value: String = self.nonEmpty(value),
              let url: URL = URL(string: value, relativeTo: baseURL)?.absoluteURL,
              let scheme: String = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else {
            return nil
        }
        return url
    }

    static func canonicalURLKey(_ url: URL) -> String {
        guard var components: URLComponents = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return url.absoluteString
        }
        components.fragment = nil
        return components.string ?? url.absoluteString
    }

    static func sorted<T>(
        _ values: [(offset: Int, value: T, order: Double?)],
        sort: VideoEpisodeSort?
    ) -> [T] {
        guard let sort: VideoEpisodeSort, sort != .source else {
            return values.map(\.value)
        }
        return values.sorted { lhs, rhs in
            switch (lhs.order, rhs.order) {
            case let (left?, right?):
                if left == right {
                    return lhs.offset < rhs.offset
                }
                return sort == .ascending ? left < right : left > right
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            case (nil, nil):
                return lhs.offset < rhs.offset
            }
        }.map(\.value)
    }

    private static func rootArrayResolution(_ object: Any) -> VideoRuleJSONArrayResolution {
        if object is NSNull {
            return VideoRuleJSONArrayResolution(state: .null, values: [])
        }
        guard let array: [Any] = object as? [Any] else {
            return VideoRuleJSONArrayResolution(state: .typeMismatch, values: [])
        }
        return VideoRuleJSONArrayResolution(
            state: array.isEmpty ? .empty : .nonEmpty,
            values: array
        )
    }

    private static func objectResolution(value: Any) -> VideoRuleJSONObjectResolution {
        if value is NSNull {
            return VideoRuleJSONObjectResolution(state: .null, value: nil)
        }
        guard let dictionary: [String: Any] = value as? [String: Any] else {
            return VideoRuleJSONObjectResolution(state: .typeMismatch, value: nil)
        }
        return VideoRuleJSONObjectResolution(
            state: dictionary.isEmpty ? .empty : .nonEmpty,
            value: dictionary
        )
    }

    private static func missingObjectResolution(
        at path: String,
        in object: Any
    ) -> VideoRuleJSONObjectResolution {
        var current: Any = object
        for segment in self.pathSegments(path) {
            if current is NSNull {
                return VideoRuleJSONObjectResolution(state: .null, value: nil)
            }
            guard segment.expandsArray == false,
                  let dictionary: [String: Any] = current as? [String: Any] else {
                return VideoRuleJSONObjectResolution(state: .typeMismatch, value: nil)
            }
            guard let child: Any = dictionary[segment.key] else {
                return VideoRuleJSONObjectResolution(state: .missing, value: nil)
            }
            current = child
        }
        return self.objectResolution(value: current)
    }

    private static func pathSegments(_ path: String) -> [(key: String, expandsArray: Bool)] {
        return path.split(separator: ".", omittingEmptySubsequences: false).compactMap { raw in
            let segment: String = String(raw)
            guard segment.isEmpty == false else {
                return nil
            }
            if segment.hasSuffix("[]") {
                return (String(segment.dropLast(2)), true)
            }
            return (segment, false)
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let normalized: String? = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized?.isEmpty == false ? normalized : nil
    }
}
