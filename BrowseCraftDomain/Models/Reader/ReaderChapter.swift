import Foundation
import BrowseCraftCore

// 中文注释：ReaderChapter 是阅读器渲染章节页面时使用的标准化章节内容。

// 中文注释：保护页关联值会携带完整资源规则；间接存储避免 Reader 的 SwiftUI
// 深层布局在逐页传值时为最大规则关联值申请过大的真机主线程栈帧。
public indirect enum ReaderPageResource: Hashable, Sendable {
    case remoteImageURL(String)
    case protectedResource(ProtectedReaderImageReference)

    public var displayURLString: String {
        switch self {
        case .remoteImageURL(let urlString):
            return urlString
        case .protectedResource(let reference):
            return reference.displayURLString
        }
    }
}

public struct ProtectedReaderImageReference: Hashable, Sendable {
    public init(
        execution: ProtectedReaderImageExecution
    ) {
        self.execution = execution
    }

    public var displayURLString: String {
        switch self.execution {
        case .legacy(let reference):
            return reference.displayURLString
        case .pipeline(let reference):
            return reference.displayURLString
        }
    }

    public var sourceID: String {
        switch self.execution {
        case .legacy(let reference):
            return reference.sourceID
        case .pipeline(let reference):
            return reference.sourceID
        }
    }

    public var baseURL: URL? {
        switch self.execution {
        case .legacy(let reference):
            return reference.baseURL
        case .pipeline(let reference):
            return reference.baseURL
        }
    }

    public var execution: ProtectedReaderImageExecution
}

/// 中文注释：Reader 只持有“如何加载受保护图片”的领域描述，不在界面层解释 Core pipeline 规则。
// 中文注释：执行描述包含 legacy 或 pipeline 完整规则，保持引用大小后再传入图片子 View。
public indirect enum ProtectedReaderImageExecution: Hashable, Sendable {
    case legacy(LegacyProtectedReaderImageReference)
    case pipeline(ResourcePipelineReaderImageReference)
}

public struct LegacyProtectedReaderImageReference: Hashable, Sendable {
    public init(
        displayURLString: String,
        sourceID: String,
        baseURL: URL? = nil,
        rule: ProtectedResourceRule,
        parameters: [String: String]
    ) {
        self.displayURLString = displayURLString
        self.sourceID = sourceID
        self.baseURL = baseURL
        self.rule = rule
        self.parameters = parameters
    }

    public var displayURLString: String
    public var sourceID: String
    public var baseURL: URL?
    public var rule: ProtectedResourceRule
    public var parameters: [String: String]
}

public struct ResourcePipelineReaderImageReference: Hashable, Sendable {
    public init(
        displayURLString: String,
        sourceID: String,
        baseURL: URL? = nil,
        rule: ResourcePipelineRule,
        item: [String: ReaderResourcePipelineValue],
        root: [String: ReaderResourcePipelineValue],
        context: [String: ReaderResourcePipelineValue],
        legacyFallback: LegacyProtectedReaderImageReference? = nil
    ) {
        self.displayURLString = displayURLString
        self.sourceID = sourceID
        self.baseURL = baseURL
        self.rule = rule
        self.item = item
        self.root = root
        self.context = context
        self.legacyFallback = legacyFallback
    }

    public var displayURLString: String
    public var sourceID: String
    public var baseURL: URL?
    public var rule: ResourcePipelineRule
    public var item: [String: ReaderResourcePipelineValue]
    public var root: [String: ReaderResourcePipelineValue]
    public var context: [String: ReaderResourcePipelineValue]
    /// 中文注释：只有 executionPolicy 明确允许时才携带旧链路；nil 表示 pipeline 失败必须直接失败。
    public var legacyFallback: LegacyProtectedReaderImageReference?
}

/// 中文注释：JSON scope 的稳定值合同放在 Domain，避免 Reader 依赖 Application 执行器内部类型。
public indirect enum ReaderResourcePipelineValue: Hashable, Sendable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case object([String: ReaderResourcePipelineValue])
    case array([ReaderResourcePipelineValue])
    case null
}

/// 中文注释：标准化的阅读页解析结果。
/// 中文注释：它表示某一章的阅读内容，上层不需要关心来源是 HTML、JSON 还是其他格式。
public struct ReaderChapter: Hashable, Sendable {
    public init(
        sourceId: String,
        comicTitle: String? = nil,
        chapterTitle: String? = nil,
        chapterURL: String,
        catalogURL: String? = nil,
        previousChapterURL: String? = nil,
        nextChapterURL: String? = nil,
        pageImageURLs: [String],
        pageResources: [ReaderPageResource] = [],
        pageImageHeaders: [String: [String: String]] = [:]
    ) {
        self.sourceId = sourceId
        self.comicTitle = comicTitle
        self.chapterTitle = chapterTitle
        self.chapterURL = chapterURL
        self.catalogURL = catalogURL
        self.previousChapterURL = previousChapterURL
        self.nextChapterURL = nextChapterURL
        self.pageImageURLs = pageImageURLs
        self.pageResources = pageResources
        self.pageImageHeaders = pageImageHeaders
    }

    public var sourceId: String
    public var comicTitle: String?
    public var chapterTitle: String?
    public var chapterURL: String
    public var catalogURL: String?
    public var previousChapterURL: String?
    public var nextChapterURL: String?
    public var pageImageURLs: [String]
    public var pageResources: [ReaderPageResource] = []
    public var pageImageHeaders: [String: [String: String]] = [:]
}
