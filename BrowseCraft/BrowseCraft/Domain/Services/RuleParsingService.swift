import Foundation

// 中文注释：RuleParsingService.swift 属于领域服务协议层，用于说明本文件承载的核心职责。

/// 中文注释：规则解析服务协议，把原始页面文档转换成应用内部统一模型。
/// 中文注释：生产环境目前用 SwiftSoup 解析 HTML，但上层只依赖这个协议，方便以后替换解析器。
protocol RuleParsingService {
    /// 中文注释：parseList 方法封装当前类型的一段业务或界面行为。
    func parseList(html: String, source: Source) throws -> [ContentItem]
    func parseList(html: String, source: Source, listRule: ListRule) throws -> [ContentItem]
    func parseList(
        html: String,
        source: Source,
        listRule: ListRule,
        context: ListContext?,
        sections: [SectionRule]?
    ) throws -> [ContentItem]
    /// 中文注释：parseDetailChapters 方法封装当前类型的一段业务或界面行为。
    func parseDetailChapters(html: String, source: Source, pageURL: String) throws -> [ChapterLink]
    func parseDetailChapters(
        html: String,
        source: Source,
        pageURL: String,
        context: ListContext?
    ) throws -> [ChapterLink]
    func parseDetailChapters(
        html: String,
        source: Source,
        detailRule: DetailRule,
        pageURL: String,
        context: ListContext?
    ) throws -> [ChapterLink]
    /// 中文注释：parseReader 方法封装当前类型的一段业务或界面行为。
    func parseReader(html: String, source: Source, pageURL: String) throws -> ReaderChapter
    func parseReader(
        html: String,
        source: Source,
        pageURL: String,
        context: ListContext?
    ) throws -> ReaderChapter
    func parseReader(
        html: String,
        source: Source,
        galleryRule: GalleryRule,
        pageURL: String,
        context: ListContext?
    ) throws -> ReaderChapter
}

extension RuleParsingService {
    /// 中文注释：P1-5.1 先在解析结果上附加列表上下文；具体 Section DOM 拆分留到后续步骤。
    func parseList(html: String, source: Source, listRule: ListRule, context: ListContext?) throws -> [ContentItem] {
        return try self.parseList(
            html: html,
            source: source,
            listRule: listRule,
            context: context,
            sections: nil
        )
    }

    /// 中文注释：P1-5.2 增加 sections 参数；默认实现不解析区块，具体解析器可覆盖为 section-aware 行为。
    func parseList(
        html: String,
        source: Source,
        listRule: ListRule,
        context: ListContext?,
        sections: [SectionRule]?
    ) throws -> [ContentItem] {
        let items: [ContentItem] = try self.parseList(
            html: html,
            source: source,
            listRule: listRule
        )

        return items.map { item in
            var contextualItem: ContentItem = item
            contextualItem.listContext = context
            return contextualItem
        }
    }

    /// 中文注释：P1-5.3 默认保持旧解析行为；支持上下文的解析器可覆盖并按来源区块缩小 Detail 作用域。
    func parseDetailChapters(
        html: String,
        source: Source,
        pageURL: String,
        context: ListContext?
    ) throws -> [ChapterLink] {
        return try self.parseDetailChapters(
            html: html,
            source: source,
            pageURL: pageURL
        )
    }

    /// 中文注释：P2-5.3 新增显式规则入口；默认回落到旧入口，避免一次性改动所有测试替身。
    func parseDetailChapters(
        html: String,
        source: Source,
        detailRule: DetailRule,
        pageURL: String,
        context: ListContext?
    ) throws -> [ChapterLink] {
        return try self.parseDetailChapters(
            html: html,
            source: source,
            pageURL: pageURL,
            context: context
        )
    }

    /// 中文注释：P1-5.3 默认保持旧解析行为；支持上下文的解析器可覆盖并按来源区块缩小 Reader 作用域。
    func parseReader(
        html: String,
        source: Source,
        pageURL: String,
        context: ListContext?
    ) throws -> ReaderChapter {
        return try self.parseReader(
            html: html,
            source: source,
            pageURL: pageURL
        )
    }

    /// 中文注释：P2-5.3 新增显式规则入口；默认回落到旧入口，避免一次性改动所有测试替身。
    func parseReader(
        html: String,
        source: Source,
        galleryRule: GalleryRule,
        pageURL: String,
        context: ListContext?
    ) throws -> ReaderChapter {
        return try self.parseReader(
            html: html,
            source: source,
            pageURL: pageURL,
            context: context
        )
    }
}
