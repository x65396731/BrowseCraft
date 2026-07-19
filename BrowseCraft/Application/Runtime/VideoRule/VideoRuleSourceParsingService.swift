import Foundation
import BrowseCraftCore

// 中文注释：VideoRuleSourceParsingService 是 Video V2 runtime 的 HTML 解析边界；加载链路不得依赖 SwiftSoup。

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

protocol VideoRuleSourceParsingService {
    func parseList(
        html: String,
        pageURL: URL,
        rule: VideoListRule
    ) throws -> VideoRuleParsedList
}

enum VideoRuleSourceParsingError: LocalizedError {
    case unsupportedSelectorKind(SelectorKind)
    case unsupportedFunction(ExtractFunction)
    case readySelectorEmpty(ruleID: String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSelectorKind(let kind):
            return "Video V2 parser does not support selectorKind=\(kind.rawValue)."
        case .unsupportedFunction(let function):
            return "Video V2 parser does not support function=\(function.rawValue)."
        case .readySelectorEmpty(let ruleID):
            return "Video V2 list readiness selector produced no output for rule \(ruleID)."
        }
    }
}
