import CoreFoundation
import Foundation

// 中文注释：ComicRuleJSONResolver 只处理 JSON Path、标量转换、数组状态和规则排序。
struct ComicRuleJSONResolver {
    enum JSONArrayState: String, Equatable {
        case missing
        case null
        case typeMismatch
        case empty
        case nonEmpty
    }

    struct JSONArrayResolution {
        let state: JSONArrayState
        let values: [Any]
    }

    static func firstJSONValue(at path: String, in object: Any) -> Any? {
        return self.jsonValues(at: path, in: object).first
    }

    static func jsonValues(at path: String, in object: Any) -> [Any] {
        let segments: [String] = path
            .split(separator: ".")
            .map(String.init)
            .filter { segment in segment.isEmpty == false }

        return segments.reduce([object]) { values, segment in
            let shouldFlattenArray: Bool = segment.hasSuffix("[]")
            let key: String = shouldFlattenArray ? String(segment.dropLast(2)) : segment
            var nextValues: [Any] = []

            for value: Any in values {
                if key.isEmpty {
                    nextValues.append(value)
                } else if let dictionary: [String: Any] = value as? [String: Any],
                          let child: Any = dictionary[key] {
                    nextValues.append(child)
                }
            }

            if shouldFlattenArray {
                return nextValues.flatMap { value in
                    return value as? [Any] ?? []
                }
            }

            return nextValues
        }
    }

    /// 中文注释：一次解析同时返回 itemPath 状态和值，避免状态判断与字段映射重复遍历后产生分歧。
    static func jsonArrayResolution(at path: String, in object: Any) -> JSONArrayResolution {
        let segments: [String] = path
            .split(separator: ".")
            .map(String.init)
            .filter { segment in segment.isEmpty == false }
        guard segments.isEmpty == false,
              segments.contains(where: { $0.hasSuffix("[]") }) else {
            return JSONArrayResolution(state: .missing, values: [])
        }

        var values: [Any] = [object]
        var encounteredArray: Bool = false

        for segment: String in segments {
            let shouldFlattenArray: Bool = segment.hasSuffix("[]")
            let key: String = shouldFlattenArray ? String(segment.dropLast(2)) : segment
            var nextValues: [Any] = []
            var foundNull: Bool = false
            var foundTypeMismatch: Bool = false

            for value: Any in values {
                let child: Any?
                if key.isEmpty {
                    child = value
                } else if let dictionary: [String: Any] = value as? [String: Any] {
                    child = dictionary[key]
                } else {
                    child = nil
                    foundTypeMismatch = true
                }

                guard let child: Any else {
                    continue
                }
                if child is NSNull {
                    foundNull = true
                    continue
                }

                if shouldFlattenArray {
                    guard let array: [Any] = child as? [Any] else {
                        foundTypeMismatch = true
                        continue
                    }
                    encounteredArray = true
                    nextValues.append(contentsOf: array)
                } else {
                    nextValues.append(child)
                }
            }

            guard nextValues.isEmpty == false else {
                if shouldFlattenArray,
                   encounteredArray,
                   foundTypeMismatch == false,
                   foundNull == false {
                    return JSONArrayResolution(state: .empty, values: [])
                }
                if foundTypeMismatch {
                    return JSONArrayResolution(state: .typeMismatch, values: [])
                }
                if foundNull {
                    return JSONArrayResolution(state: .null, values: [])
                }
                if encounteredArray && values.isEmpty {
                    return JSONArrayResolution(state: .empty, values: [])
                }
                return JSONArrayResolution(state: .missing, values: [])
            }
            values = nextValues
        }

        guard encounteredArray else {
            return JSONArrayResolution(state: .missing, values: [])
        }
        return JSONArrayResolution(
            state: values.isEmpty ? .empty : .nonEmpty,
            values: values
        )
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

    /// 中文注释：规则声明的状态值保持 JSON 标量类型，避免把 true、1 和 "1" 混为同一语义。
    static func responseScalar(_ value: Any?) -> APIResponseScalar? {
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

    static func sortedValues(_ values: [(value: Any, order: Double?)], sort: ChapterSort?) -> [Any] {
        guard let sort: ChapterSort = sort,
              sort != .none,
              values.contains(where: { pair in pair.order != nil }) else {
            return []
        }

        return values.sorted { lhs, rhs in
            let lhsOrder: Double = lhs.order ?? 0
            let rhsOrder: Double = rhs.order ?? 0

            switch sort {
            case .ascending:
                return lhsOrder < rhsOrder
            case .descending:
                return lhsOrder > rhsOrder
            case .none:
                return false
            }
        }
        .map(\.value)
    }
}
