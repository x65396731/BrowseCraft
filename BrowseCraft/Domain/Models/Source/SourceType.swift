import Foundation

// 中文注释：SourceType.swift 属于领域模型层，用于说明本文件承载的核心职责。

/// 中文注释：源站原始数据格式，用于描述解析前的站点类型。
enum SourceType: String, Codable, CaseIterable, Identifiable, Hashable {
    case rss
    case html
    case json
    case xml

    var id: String {
        return self.rawValue
    }
}

