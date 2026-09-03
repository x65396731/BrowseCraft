import BrowseCraftCore
import BrowseCraftDomain
import Combine
import Foundation

struct SourceLoadingState: Equatable {
    let sourceID: String
    let sourceName: String
    let runtimeKind: SourceRuntimeKind
}

struct SourceLibraryPageSnapshot: Equatable {
    let pageNumber: Int
    let items: [ContentItem]
    let nextPage: Int?
}

struct SourceLibrarySnapshot: Equatable {
    let source: Source
    let sourceID: String
    let sourceName: String
    let runtimeKind: SourceRuntimeKind
    let listContext: ListContext?
    let pages: [SourceLibraryPageSnapshot]

    var items: [ContentItem] {
        var seenItemIDs: Set<String> = []
        return self.pages
            .flatMap(\.items)
            .filter { item in
                return seenItemIDs.insert(item.id).inserted
            }
    }
}

// 中文注释：SourceSelectionStore 保存 Sources 与 Library 之间共享的当前 source 和当前 runtime 快照。
final class SourceSelectionStore: ObservableObject {
    @Published var selectedSourceID: String?
    @Published var preparingSource: SourceLoadingState?
    @Published var preparedLibrarySnapshot: SourceLibrarySnapshot?

    func beginPreparingSource(_ source: Source) {
        self.preparingSource = SourceLoadingState(
            sourceID: source.id,
            sourceName: source.name,
            runtimeKind: source.configuration.kind
        )
    }

    func endPreparingSource(id sourceID: String) {
        if self.preparingSource?.sourceID == sourceID {
            self.preparingSource = nil
        }
    }

    func publishLibrarySnapshot(
        source: Source,
        items: [ContentItem],
        listContext: ListContext? = nil,
        pageNumber: Int = 1,
        nextPage: Int? = nil
    ) {
        self.publishLibrarySnapshot(
            source: source,
            pages: [
                SourceLibraryPageSnapshot(
                    pageNumber: pageNumber,
                    items: items,
                    nextPage: nextPage
                )
            ],
            listContext: listContext
        )
    }

    func publishLibrarySnapshot(
        source: Source,
        pages: [SourceLibraryPageSnapshot],
        listContext: ListContext? = nil
    ) {
        let orderedPages: [SourceLibraryPageSnapshot] = pages.sorted { lhs, rhs in
            return lhs.pageNumber < rhs.pageNumber
        }
        self.preparedLibrarySnapshot = SourceLibrarySnapshot(
            source: source,
            sourceID: source.id,
            sourceName: source.name,
            runtimeKind: source.configuration.kind,
            listContext: listContext ?? orderedPages.first?.items.first?.listContext,
            pages: orderedPages
        )
    }
}
