import Foundation

// 中文注释：SourceType 只描述源站原始数据格式，不再作为 runtime 分发入口。

/// 中文注释：源站原始数据格式，用于描述解析前的站点类型。
public enum SourceType: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case rss
    case html
    case json
    case xml

    public var id: String {
        return self.rawValue
    }
}
