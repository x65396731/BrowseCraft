import Foundation

// 中文注释：ContentType.swift 属于领域模型层，用于说明本文件承载的核心职责。

/// 中文注释：BrowseCraft 可展示的标准内容类型。
/// 中文注释：源站可以是 HTML、RSS、JSON 或 XML，解析后统一映射为这些应用级类型。
enum ContentType: String, Codable, CaseIterable, Identifiable, Hashable {
    case comic
    case video
    case article
    case gallery

    var id: String {
        return self.rawValue
    }
}

