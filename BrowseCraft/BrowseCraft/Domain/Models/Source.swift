import Foundation

// 中文注释：Source.swift 属于领域模型层，用于说明本文件承载的核心职责。

/// 中文注释：用户添加的内容源模型。
/// 中文注释：Source 持有 SiteRule，规则告诉解析器如何查找列表、标题、封面、章节、图片和视频。
struct Source: Identifiable, Hashable {
    var id: String
    var name: String
    var baseURL: String
    var type: SourceType
    var rule: SiteRule
    var enabled: Bool
    var createdAt: Date
    var updatedAt: Date
}

extension Source {
    /// 中文注释：内置规则由 BrowseCraftRulesKit 同步，编辑器只能复制后修改，避免刷新时覆盖用户改动。
    var isBuiltIn: Bool {
        return self.id.hasPrefix("built-in.")
    }
}
