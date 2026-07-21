import Foundation
import BrowseCraftCore

// 中文注释：ReaderChapter 是阅读器渲染章节页面时使用的标准化章节内容。

// 中文注释：保护页关联值会携带完整资源规则；间接存储避免 Reader 的 SwiftUI
// 深层布局在逐页传值时为最大规则关联值申请过大的真机主线程栈帧。
indirect enum ReaderPageResource: Hashable {
    case remoteImageURL(String)
    case protectedResource(ProtectedReaderImageReference)

    var displayURLString: String {
        switch self {
        case .remoteImageURL(let urlString):
            return urlString
        case .protectedResource(let reference):
            return reference.displayURLString
        }
    }
}

struct ProtectedReaderImageReference: Hashable {
    var displayURLString: String {
        switch self.execution {
        case .legacy(let reference):
            return reference.displayURLString
        case .pipeline(let reference):
            return reference.displayURLString
        }
    }

    var sourceID: String {
        switch self.execution {
        case .legacy(let reference):
            return reference.sourceID
        case .pipeline(let reference):
            return reference.sourceID
        }
    }

    var baseURL: URL? {
        switch self.execution {
        case .legacy(let reference):
            return reference.baseURL
        case .pipeline(let reference):
            return reference.baseURL
        }
    }

    var execution: ProtectedReaderImageExecution
}

/// 中文注释：Reader 只持有“如何加载受保护图片”的领域描述，不在界面层解释 Core pipeline 规则。
// 中文注释：执行描述包含 legacy 或 pipeline 完整规则，保持引用大小后再传入图片子 View。
indirect enum ProtectedReaderImageExecution: Hashable {
    case legacy(LegacyProtectedReaderImageReference)
    case pipeline(ResourcePipelineReaderImageReference)
}

struct LegacyProtectedReaderImageReference: Hashable {
    var displayURLString: String
    var sourceID: String
    var baseURL: URL?
    var rule: ProtectedResourceRule
    var parameters: [String: String]
}

struct ResourcePipelineReaderImageReference: Hashable {
    var displayURLString: String
    var sourceID: String
    var baseURL: URL?
    var rule: ResourcePipelineRule
    var item: [String: ReaderResourcePipelineValue]
    var root: [String: ReaderResourcePipelineValue]
    var context: [String: ReaderResourcePipelineValue]
    /// 中文注释：只有 executionPolicy 明确允许时才携带旧链路；nil 表示 pipeline 失败必须直接失败。
    var legacyFallback: LegacyProtectedReaderImageReference?
}

/// 中文注释：JSON scope 的稳定值合同放在 Domain，避免 Reader 依赖 Application 执行器内部类型。
indirect enum ReaderResourcePipelineValue: Hashable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case object([String: ReaderResourcePipelineValue])
    case array([ReaderResourcePipelineValue])
    case null
}

/// 中文注释：标准化的阅读页解析结果。
/// 中文注释：它表示某一章的阅读内容，上层不需要关心来源是 HTML、JSON 还是其他格式。
struct ReaderChapter: Hashable {
    var sourceId: String
    var comicTitle: String?
    var chapterTitle: String?
    var chapterURL: String
    var catalogURL: String?
    var previousChapterURL: String?
    var nextChapterURL: String?
    var pageImageURLs: [String]
    var pageResources: [ReaderPageResource] = []
    var pageImageHeaders: [String: [String: String]] = [:]
}
