import Foundation

// 中文注释：ContentItem 是 SourceRuntime 输出给列表、书架和历史功能使用的统一内容条目。

/// 中文注释：BrowseCraft 在 Library 中展示的标准化内容条目。
/// 中文注释：原始来源可以是网页、RSS、JSON 或 XML，解析后 UI 只需要这个统一模型。
struct ContentItem: Identifiable, Hashable {
    var id: String
    var sourceId: String
    var title: String
    var detailURL: String
    var coverURL: String?
    var type: SourceContentKind
    var latestText: String?
    var updatedAt: Date?
    /// 中文注释：记录当前列表快照内的展示顺序，缓存读取时用它恢复规则解析出的网页顺序。
    var listOrder: Int? = nil
    /// 中文注释：记录列表项来自哪个页面、Tab 或 Section，后续详情/阅读页可用它缩小解析范围。
    var listContext: ListContext? = nil
}

// 中文注释：RSSContentPayload 是 RSS 详情页的富内容载体，通过 latestText 临时透传，不进入 Core runtime 模型。
struct RSSContentPayload: Codable, Equatable, Hashable {
    enum BlockKind: String, Codable {
        case paragraph
        case subtitle
        case image
    }

    struct Metadata: Codable, Equatable, Hashable {
        var tags: [String] = []
        var likeCount: Int?
        var commentCount: Int?
    }

    struct Block: Codable, Equatable, Hashable, Identifiable {
        var id: String
        var kind: BlockKind
        var text: String?
        var imageURL: String?
    }

    var summary: String?
    var blocks: [Block]
    var metadata: Metadata?

    var summaryText: String? {
        if let summary: String = self.summary?.trimmedNonEmpty {
            return summary
        }

        return self.blocks.compactMap(\.text).first?.trimmedNonEmpty
    }

    func encodedString() -> String? {
        guard let data: Data = try? JSONEncoder().encode(self) else {
            return nil
        }

        return Self.prefix + data.base64EncodedString()
    }

    static func decode(from string: String?) -> RSSContentPayload? {
        guard let string: String = string,
              string.hasPrefix(Self.prefix) else {
            return nil
        }

        let payloadString: String = String(string.dropFirst(Self.prefix.count))
        guard let data: Data = Data(base64Encoded: payloadString) else {
            return nil
        }

        return try? JSONDecoder().decode(RSSContentPayload.self, from: data)
    }

    private static let prefix: String = "__BROWSECRAFT_RSS_CONTENT_V1__"
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed: String = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
