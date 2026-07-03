import Foundation
import BrowseCraftCore

// 中文注释：SourceRuntimeInputBridge 把 App 的入口上下文转换成 Core runtime input，不执行解析或请求。
struct SourceRuntimeInputBridge {
    func context(
        source: Source,
        listContext: ListContext? = nil,
        ruleID: String? = nil,
        operation: SourceRuntimeOperation? = nil,
        urlOverride: URL? = nil,
        headers: [String: String] = [:],
        debugMode: Bool = false
    ) -> SourceRuntimeContext {
        return SourceRuntimeContext(
            sourceID: source.id,
            pageID: listContext?.pageId,
            tabID: listContext?.tabId,
            sectionID: listContext?.sectionId,
            sectionRole: listContext?.sectionRole?.rawValue,
            ruleID: ruleID ?? listContext?.listRuleId,
            requestOverride: self.requestOverride(url: urlOverride, headers: headers),
            debugMode: debugMode,
            operation: operation
        )
    }

    func listInput(
        source: Source,
        page: Int,
        listContext: ListContext?,
        urlOverride: URL? = nil,
        headers: [String: String] = [:],
        debugMode: Bool = false
    ) -> SourceListInput {
        return SourceListInput(
            page: page,
            urlOverride: urlOverride,
            context: self.context(
                source: source,
                listContext: listContext,
                ruleID: listContext?.listRuleId,
                operation: .list,
                urlOverride: urlOverride,
                headers: headers,
                debugMode: debugMode
            )
        )
    }

    func searchInput(
        source: Source,
        keyword: String,
        page: Int,
        listContext: ListContext?,
        ruleID: String?,
        urlOverride: URL? = nil,
        headers: [String: String] = [:],
        debugMode: Bool = false
    ) -> SourceSearchInput {
        return SourceSearchInput(
            keyword: keyword,
            page: page,
            urlOverride: urlOverride,
            context: self.context(
                source: source,
                listContext: listContext,
                ruleID: ruleID,
                operation: .search,
                urlOverride: urlOverride,
                headers: headers,
                debugMode: debugMode
            )
        )
    }

    func detailInput(
        source: Source,
        detailURLString: String,
        listContext: ListContext?,
        ruleID: String?,
        debugMode: Bool = false
    ) -> SourceDetailInput? {
        guard let detailURL: URL = self.url(from: detailURLString) else {
            return nil
        }

        return SourceDetailInput(
            detailURL: detailURL,
            context: self.context(
                source: source,
                listContext: listContext,
                ruleID: ruleID,
                operation: .detail,
                debugMode: debugMode
            )
        )
    }

    func readerInput(
        source: Source,
        chapterURLString: String,
        listContext: ListContext?,
        ruleID: String?,
        debugMode: Bool = false
    ) -> SourceReaderInput? {
        guard let chapterURL: URL = self.url(from: chapterURLString) else {
            return nil
        }

        return SourceReaderInput(
            chapterURL: chapterURL,
            context: self.context(
                source: source,
                listContext: listContext,
                ruleID: ruleID,
                operation: .reader,
                debugMode: debugMode
            )
        )
    }

    private func requestOverride(url: URL?, headers: [String: String]) -> SourceRequestOverride? {
        guard url != nil || headers.isEmpty == false else {
            return nil
        }

        return SourceRequestOverride(url: url, headers: headers)
    }

    private func url(from string: String) -> URL? {
        let normalizedString: String = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedString.isEmpty == false else {
            return nil
        }

        return URL(string: normalizedString)
    }
}
