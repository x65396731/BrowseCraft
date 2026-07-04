import BrowseCraftCore

// 中文注释：P3-5.1 只建立 App 规则模型到 Core 轻量 primitive 的映射，不迁移 SiteRule 大模型。
extension RuleDebugStage {
    var sourceRuntimeOperation: SourceRuntimeOperation {
        switch self {
        case .list:
            return .list
        case .search:
            return .search
        case .detail:
            return .detail
        case .reader:
            return .reader
        }
    }
}

extension SourceRuntimeOperation {
    var ruleDebugStage: RuleDebugStage? {
        switch self {
        case .list:
            return .list
        case .search:
            return .search
        case .detail:
            return .detail
        case .reader:
            return .reader
        case .debug:
            return nil
        }
    }
}

extension RuleDebugField {
    var sourceRuleField: SourceRuleField {
        switch self {
        case .item:
            return .item
        case .title:
            return .title
        case .link:
            return .link
        case .cover:
            return .cover
        case .latestText:
            return .latestText
        case .chapter:
            return .chapter
        case .image:
            return .image
        case .unknown:
            return .unknown
        }
    }
}

extension RuleCandidateField {
    var sourceRuleField: SourceRuleField {
        switch self {
        case .section:
            return .section
        case .item:
            return .item
        case .title:
            return .title
        case .link:
            return .link
        case .cover:
            return .cover
        case .latestText:
            return .latestText
        case .chapterContainer:
            return .chapterContainer
        case .chapterItem:
            return .chapterItem
        case .chapterTitle:
            return .chapterTitle
        case .chapterLink:
            return .chapterLink
        case .image:
            return .image
        case .nextPage:
            return .nextPage
        case .unknown:
            return .unknown
        }
    }
}

extension SelectorKind {
    var sourceRuleSelectorKind: SourceRuleSelectorKind {
        switch self {
        case .css:
            return .css
        case .jsonPath:
            return .jsonPath
        case .xpath:
            return .xpath
        case .current:
            return .current
        }
    }
}

extension SourceRuleSelectorKind {
    var selectorKind: SelectorKind {
        switch self {
        case .css:
            return .css
        case .jsonPath:
            return .jsonPath
        case .xpath:
            return .xpath
        case .current:
            return .current
        }
    }
}

extension ExtractFunction {
    var sourceRuleExtractFunction: SourceRuleExtractFunction {
        switch self {
        case .text:
            return .text
        case .html:
            return .html
        case .attr:
            return .attr
        case .raw:
            return .raw
        case .url:
            return .url
        case .decodeBase64:
            return .decodeBase64
        case .removingPercentEncoding:
            return .removingPercentEncoding
        case .addingPercentEncoding:
            return .addingPercentEncoding
        case .replace:
            return .replace
        case .decompressFromBase64:
            return .decompressFromBase64
        case .reversed:
            return .reversed
        case .regexReplacement:
            return .regexReplacement
        }
    }
}

extension SourceRuleExtractFunction {
    var extractFunction: ExtractFunction {
        switch self {
        case .text:
            return .text
        case .html:
            return .html
        case .attr:
            return .attr
        case .raw:
            return .raw
        case .url:
            return .url
        case .decodeBase64:
            return .decodeBase64
        case .removingPercentEncoding:
            return .removingPercentEncoding
        case .addingPercentEncoding:
            return .addingPercentEncoding
        case .replace:
            return .replace
        case .decompressFromBase64:
            return .decompressFromBase64
        case .reversed:
            return .reversed
        case .regexReplacement:
            return .regexReplacement
        }
    }
}
