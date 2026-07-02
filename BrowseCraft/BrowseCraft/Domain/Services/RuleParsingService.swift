import Foundation

// 中文注释：RuleParsingService.swift 属于领域服务协议层，用于说明本文件承载的核心职责。

/// 中文注释：规则解析服务协议，把原始页面文档转换成应用内部统一模型。
/// 中文注释：生产环境目前用 SwiftSoup 解析 HTML，但上层只依赖这个协议，方便以后替换解析器。
protocol RuleParsingService {
    /// 中文注释：parseList 方法封装当前类型的一段业务或界面行为。
    func parseList(html: String, source: Source) throws -> [ContentItem]
    func parseList(html: String, source: Source, listRule: ListRule) throws -> [ContentItem]
    /// 中文注释：parseDetailChapters 方法封装当前类型的一段业务或界面行为。
    func parseDetailChapters(html: String, source: Source, pageURL: String) throws -> [ChapterLink]
    /// 中文注释：parseReader 方法封装当前类型的一段业务或界面行为。
    func parseReader(html: String, source: Source, pageURL: String) throws -> ReaderChapter
}
