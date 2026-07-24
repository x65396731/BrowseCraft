import Foundation

// 中文注释：App 仅保留受保护资源与请求模板所需的 JSON Path/字符串读取。
// 中文注释：漫画 API 响应合同、数组状态、排序和字段映射统一由 BrowseCraftCore 解释。
struct ComicRuleJSONResolver {
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

}
