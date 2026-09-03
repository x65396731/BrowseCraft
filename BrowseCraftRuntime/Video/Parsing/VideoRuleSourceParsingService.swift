import Foundation
import BrowseCraftCore

// 中文注释：VideoRuleSourceParsingService 是 Loader 与 Core 解析适配器之间的
// 内部测试边界；加载链路不依赖 SwiftSoup，也不自行解释 selector。

public struct VideoRuleParsedListItem: Hashable, Sendable {
    public init(
        idCode: String? = nil,
        title: String,
        detailURL: URL,
        coverURL: URL? = nil,
        latestText: String? = nil
    ) {
        self.idCode = idCode
        self.title = title
        self.detailURL = detailURL
        self.coverURL = coverURL
        self.latestText = latestText
    }

    public var idCode: String?
    public var title: String
    public var detailURL: URL
    public var coverURL: URL?
    public var latestText: String?
}

public struct VideoRuleParsedList: Hashable, Sendable {
    public init(
        items: [VideoRuleParsedListItem],
        candidateCount: Int,
        droppedCount: Int
    ) {
        self.items = items
        self.candidateCount = candidateCount
        self.droppedCount = droppedCount
    }

    public var items: [VideoRuleParsedListItem]
    public var candidateCount: Int
    public var droppedCount: Int
}

/// 中文注释：字段 id 仅供 App 临时适配结果和测试定位，最终输出使用 Core metadata。
public struct VideoRuleParsedDetailAttribute: Hashable, Sendable {
    public init(
        id: String,
        label: String? = nil,
        value: String
    ) {
        self.id = id
        self.label = label
        self.value = value
    }

    public var id: String
    public var label: String?
    public var value: String
}

public struct VideoRuleParsedDetailMetadata: Hashable, Sendable {
    public init(
        idCode: String? = nil,
        title: String? = nil,
        coverURL: URL? = nil,
        description: String? = nil,
        attributes: [VideoRuleParsedDetailAttribute]
    ) {
        self.idCode = idCode
        self.title = title
        self.coverURL = coverURL
        self.description = description
        self.attributes = attributes
    }

    public var idCode: String?
    public var title: String?
    public var coverURL: URL?
    public var description: String?
    public var attributes: [VideoRuleParsedDetailAttribute]
}

/// 中文注释：readyMatched=false 表示 DOM 分支合法地产生 empty，供后续 sourceStrategy 决定是否 fallback。
public struct VideoRuleParsedDetail: Hashable, Sendable {
    public init(
        metadata: VideoRuleParsedDetailMetadata,
        readyMatched: Bool
    ) {
        self.metadata = metadata
        self.readyMatched = readyMatched
    }

    public var metadata: VideoRuleParsedDetailMetadata
    public var readyMatched: Bool
}

public struct VideoRuleParsedEpisode: Hashable, Sendable {
    public init(
        idCode: String? = nil,
        title: String,
        playURL: URL,
        order: Double? = nil,
        isRestricted: Bool? = nil,
        isPaid: Bool? = nil
    ) {
        self.idCode = idCode
        self.title = title
        self.playURL = playURL
        self.order = order
        self.isRestricted = isRestricted
        self.isPaid = isPaid
    }

    public var idCode: String?
    public var title: String
    public var playURL: URL
    public var order: Double?
    public var isRestricted: Bool?
    public var isPaid: Bool?
}

public struct VideoRuleParsedEpisodeGroup: Hashable, Sendable {
    public init(
        idCode: String? = nil,
        title: String? = nil,
        episodes: [VideoRuleParsedEpisode],
        candidateCount: Int,
        droppedCount: Int
    ) {
        self.idCode = idCode
        self.title = title
        self.episodes = episodes
        self.candidateCount = candidateCount
        self.droppedCount = droppedCount
    }

    public var idCode: String?
    public var title: String?
    public var episodes: [VideoRuleParsedEpisode]
    public var candidateCount: Int
    public var droppedCount: Int
}

public struct VideoRuleParsedEpisodes: Hashable, Sendable {
    public init(
        groups: [VideoRuleParsedEpisodeGroup],
        readyMatched: Bool,
        candidateCount: Int,
        droppedCount: Int
    ) {
        self.groups = groups
        self.readyMatched = readyMatched
        self.candidateCount = candidateCount
        self.droppedCount = droppedCount
    }

    public var groups: [VideoRuleParsedEpisodeGroup]
    public var readyMatched: Bool
    public var candidateCount: Int
    public var droppedCount: Int

    public var episodes: [VideoRuleParsedEpisode] {
        return self.groups.flatMap(\.episodes)
    }
}

public struct VideoRuleParsedMediaCandidate: Hashable, Sendable {
    public init(
        ruleID: String,
        title: String? = nil,
        url: URL,
        kind: VideoDirectMediaKind
    ) {
        self.ruleID = ruleID
        self.title = title
        self.url = url
        self.kind = kind
    }

    public var ruleID: String
    public var title: String?
    public var url: URL
    public var kind: VideoDirectMediaKind
}

/// 中文注释：播放解析保留有序强类型 direct media 与 iframe 结果，让 loader 按合同固定顺序决策。
public struct VideoRuleParsedPlayback: Hashable, Sendable {
    public init(
        mediaCandidates: [VideoRuleParsedMediaCandidate],
        mediaURLs: [URL],
        mediaCandidateCount: Int,
        invalidMediaURLCount: Int,
        iframeURLs: [URL],
        iframeCandidateCount: Int,
        invalidIframeURLCount: Int,
        readyMatched: Bool
    ) {
        self.mediaCandidates = mediaCandidates
        self.mediaURLs = mediaURLs
        self.mediaCandidateCount = mediaCandidateCount
        self.invalidMediaURLCount = invalidMediaURLCount
        self.iframeURLs = iframeURLs
        self.iframeCandidateCount = iframeCandidateCount
        self.invalidIframeURLCount = invalidIframeURLCount
        self.readyMatched = readyMatched
    }

    public var mediaCandidates: [VideoRuleParsedMediaCandidate]
    public var mediaURLs: [URL]
    public var mediaCandidateCount: Int
    public var invalidMediaURLCount: Int
    public var iframeURLs: [URL]
    public var iframeCandidateCount: Int
    public var invalidIframeURLCount: Int
    public var readyMatched: Bool
}

public protocol VideoRuleSourceParsingService: Sendable {
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

public enum VideoRuleSourceParsingError: LocalizedError, Sendable {
    case unsupportedSelectorKind(SelectorKind)
    case unsupportedFunction(ExtractFunction)
    case readySelectorEmpty(ruleID: String)
    case incompleteDOMRule(kind: String, ruleID: String)

    public var errorDescription: String? {
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
