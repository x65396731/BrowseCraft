import Foundation
import BrowseCraftCore

// 中文注释：ContentItem 是 App 界面、缓存和历史功能使用的投影；跨 runtime 合同由 Core SourceContentItem 承担。

/// 中文注释：BrowseCraft 在 Library 中展示的标准化内容条目。
/// 中文注释：原始来源可以是网页、RSS、JSON 或 XML，App 在 runtime 边界把 Core 输出投影为此模型。
struct ContentItem: Identifiable, Hashable {
    var id: String
    /// 中文注释：源站原始业务 id 必须跨 list → detail/episode 保留，不能从展示 id 反推。
    var idCode: String? = nil
    var sourceId: String
    var title: String
    var detailURL: String
    var coverURL: String?
    var type: SourceContentKind
    var latestText: String?
    /// 中文注释：来源详情富内容使用 Core 合同传递；latestText 仅保留列表摘要和旧缓存兼容。
    var richContent: SourceRichContent? = nil
    var updatedAt: Date?
    /// 中文注释：记录当前列表快照内的展示顺序，缓存读取时用它恢复规则解析出的网页顺序。
    var listOrder: Int? = nil
    /// 中文注释：记录列表项来自哪个页面、Tab 或 Section，后续详情/阅读页可用它缩小解析范围。
    var listContext: ListContext? = nil
}

typealias RSSContentPayload = SourceRichContent

extension SourceRichContent {
    var summaryText: String? {
        if let summary: String = self.summary?.trimmedNonEmpty {
            return summary
        }

        return self.blocks.compactMap(\.text).first?.trimmedNonEmpty
    }

    /// 中文注释：仅用于读取旧缓存；新 runtime 不再把富内容写入 latestText。
    func legacyEncodedString() -> String? {
        guard let data: Data = try? JSONEncoder().encode(self) else {
            return nil
        }

        return Self.legacyPrefix + data.base64EncodedString()
    }

    static func decode(from string: String?) -> RSSContentPayload? {
        guard let string: String = string,
              string.hasPrefix(Self.legacyPrefix) else {
            return nil
        }

        let payloadString: String = String(string.dropFirst(Self.legacyPrefix.count))
        guard let data: Data = Data(base64Encoded: payloadString) else {
            return nil
        }

        return try? JSONDecoder().decode(RSSContentPayload.self, from: data)
    }

    private static var legacyPrefix: String { "__BROWSECRAFT_RSS_CONTENT_V1__" }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed: String = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
