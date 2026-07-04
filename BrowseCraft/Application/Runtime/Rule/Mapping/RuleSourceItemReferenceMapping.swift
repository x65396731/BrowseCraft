import Foundation
import BrowseCraftCore

struct RuleSourceItemReferenceMapper {
    func reference(
        from item: ContentItem,
        handoffIntent: SourceItemHandoffIntent = .detail,
        chapter: ChapterLink? = nil,
        requestOverride: SourceRequestOverride? = nil,
        runtimeContext: SourceRuntimeContext? = nil
    ) -> SourceItemReference {
        return SourceItemReference(
            id: item.id,
            sourceID: item.sourceId,
            title: item.title,
            contentType: item.type,
            detailURL: self.url(from: item.detailURL),
            chapterURL: chapter.flatMap { chapter in
                return self.url(from: chapter.url)
            },
            coverURL: self.url(from: item.coverURL),
            latestText: item.latestText,
            listContext: self.itemListContext(from: item.listContext),
            handoffIntent: handoffIntent,
            requestOverride: requestOverride,
            runtimeContext: runtimeContext
        )
    }

    private func itemListContext(from context: ListContext?) -> SourceItemListContext? {
        guard let context: ListContext = context else {
            return nil
        }

        return SourceItemListContext(
            pageID: context.pageId,
            tabID: context.tabId,
            sectionID: context.sectionId,
            sectionRole: context.sectionRole?.rawValue,
            ruleID: context.listRuleId
        )
    }

    private func url(from string: String?) -> URL? {
        guard let string: String = string,
              string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }

        return URL(string: string)
    }
}
