import BrowseCraftCore
import BrowseCraftDomain
import Foundation

/// 中文注释：把已下发规则格式化成只读的调试 JSON，供 `SourceDebugView` 展示。
/// App 不提供任何规则创建或编辑入口（`BCA-UI-003`），因此这里只有格式化，没有写路径。
struct SourceRuleDebugJSONFormatter: Sendable {
    private let jsonEncoder: JSONEncoder

    init(jsonEncoder: JSONEncoder = JSONEncoder()) {
        self.jsonEncoder = jsonEncoder
        self.jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    }

    func formattedDebugJSON(for source: Source) -> String {
        do {
            switch source.configuration {
            case .comic(let configuration):
                return try self.formattedJSON(configuration.rule)
            case .video(let configuration):
                return try self.formattedJSON(configuration)
            case .plugin(let configuration):
                return try self.formattedJSON(configuration)
            case .book(let configuration):
                return try self.formattedJSON(configuration.rule)
            }
        } catch {
            return "{}"
        }
    }

    private func formattedJSON<Value: Encodable>(_ value: Value) throws -> String {
        let encodedValue: Data = try self.jsonEncoder.encode(value)
        return String(data: encodedValue, encoding: .utf8) ?? "{}"
    }
}
