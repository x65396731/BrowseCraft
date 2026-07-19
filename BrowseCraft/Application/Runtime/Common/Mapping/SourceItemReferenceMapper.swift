import Foundation
import BrowseCraftCore

/// Maps App navigation state into the Core handoff contract shared by all runtimes.
struct SourceItemReferenceMapper {
    func reference(
        from item: ContentItem,
        chapterURL: URL? = nil,
        intent: SourceItemHandoffIntent,
        requestOverride: SourceRequestOverride? = nil,
        runtimeContext: SourceRuntimeContext? = nil
    ) -> SourceItemReference {
        return SourceItemReference(
            id: item.id,
            sourceID: item.sourceId,
            title: item.title,
            contentType: item.type,
            detailURL: self.url(from: item.detailURL),
            chapterURL: chapterURL,
            coverURL: self.url(from: item.coverURL),
            latestText: item.latestText,
            listContext: item.listContext.map { context in
                return SourceItemListContext(
                    pageID: context.pageId,
                    tabID: context.tabId,
                    sectionID: context.sectionId,
                    sectionRole: context.sectionRole?.rawValue,
                    ruleID: context.listRuleId
                )
            },
            handoffIntent: intent,
            requestOverride: requestOverride,
            runtimeContext: runtimeContext,
            idCode: item.idCode
        )
    }

    private func url(from string: String?) -> URL? {
        guard let string: String = string?.trimmingCharacters(in: .whitespacesAndNewlines),
              string.isEmpty == false else {
            return nil
        }
        return URL(string: string)
    }
}
