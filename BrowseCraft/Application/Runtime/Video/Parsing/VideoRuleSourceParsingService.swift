import Foundation
import BrowseCraftCore

// 中文注释：VideoRuleSourceParsingService 是 Loader 与 Core 解析适配器之间的
// 内部测试边界；加载链路不依赖 SwiftSoup，也不自行解释 selector。

struct VideoRuleParsedListItem: Hashable {
    var idCode: String?
    var title: String
    var detailURL: URL
    var coverURL: URL?
    var latestText: String?
}

struct VideoRuleParsedList: Hashable {
    var items: [VideoRuleParsedListItem]
    var candidateCount: Int
    var droppedCount: Int
}

/// 中文注释：字段 id 仅供 App 临时适配结果和测试定位，最终输出使用 Core metadata。
struct VideoRuleParsedDetailAttribute: Hashable {
    var id: String
    var label: String?
    var value: String
}

struct VideoRuleParsedDetailMetadata: Hashable {
    var idCode: String?
    var title: String?
    var coverURL: URL?
    var description: String?
    var attributes: [VideoRuleParsedDetailAttribute]
}

/// 中文注释：readyMatched=false 表示 DOM 分支合法地产生 empty，供后续 sourceStrategy 决定是否 fallback。
struct VideoRuleParsedDetail: Hashable {
    var metadata: VideoRuleParsedDetailMetadata
    var readyMatched: Bool
}

struct VideoRuleParsedEpisode: Hashable {
    var idCode: String?
    var title: String
    var playURL: URL
    var order: Double?
    var isRestricted: Bool?
    var isPaid: Bool?
}

struct VideoRuleParsedEpisodeGroup: Hashable {
    var idCode: String?
    var title: String?
    var episodes: [VideoRuleParsedEpisode]
    var candidateCount: Int
    var droppedCount: Int
}

struct VideoRuleParsedEpisodes: Hashable {
    var groups: [VideoRuleParsedEpisodeGroup]
    var readyMatched: Bool
    var candidateCount: Int
    var droppedCount: Int

    var episodes: [VideoRuleParsedEpisode] {
        return self.groups.flatMap(\.episodes)
    }
}

/// 中文注释：播放解析分别保留 direct media 与 iframe 结果，让 loader 按合同固定顺序决策。
struct VideoRuleParsedPlayback: Hashable {
    var mediaURLs: [URL]
    var mediaCandidateCount: Int
    var invalidMediaURLCount: Int
    var iframeURLs: [URL]
    var iframeCandidateCount: Int
    var invalidIframeURLCount: Int
    var readyMatched: Bool
}

protocol VideoRuleSourceParsingService {
    func parseList(
        html: String,
        pageURL: URL,
        rule: VideoListRule
    ) throws -> VideoRuleParsedList

    func parseDetail(
        html: String,
        pageURL: URL,
        rule: VideoDetailRule
    ) throws -> VideoRuleParsedDetail

    func parseEpisodes(
        html: String,
        pageURL: URL,
        rule: VideoEpisodeRule
    ) throws -> VideoRuleParsedEpisodes

    func parsePlayback(
        html: String,
        pageURL: URL,
        rule: VideoPlaybackRule
    ) throws -> VideoRuleParsedPlayback
}

enum VideoRuleSourceParsingError: LocalizedError {
    case unsupportedSelectorKind(SelectorKind)
    case unsupportedFunction(ExtractFunction)
    case readySelectorEmpty(ruleID: String)
    case incompleteDOMRule(kind: String, ruleID: String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSelectorKind(let kind):
            return "Video V2 parser does not support selectorKind=\(kind.rawValue)."
        case .unsupportedFunction(let function):
            return "Video V2 parser does not support function=\(function.rawValue)."
        case .readySelectorEmpty(let ruleID):
            return "Video V2 list readiness selector produced no output for rule \(ruleID)."
        case .incompleteDOMRule(let kind, let ruleID):
            return "Video V2 \(kind) DOM rule is incomplete: \(ruleID)."
        }
    }
}
