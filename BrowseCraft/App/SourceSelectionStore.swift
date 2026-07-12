import Combine
import Foundation

struct SourceLoadingState: Equatable {
    let sourceID: String
    let sourceName: String
    let runtimeKind: SourceRuntimeKind
}

struct SourceLibrarySnapshot: Equatable {
    let source: Source
    let sourceID: String
    let sourceName: String
    let runtimeKind: SourceRuntimeKind
    let listContext: ListContext?
    let items: [ContentItem]
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
        listContext: ListContext? = nil
    ) {
        self.preparedLibrarySnapshot = SourceLibrarySnapshot(
            source: source,
            sourceID: source.id,
            sourceName: source.name,
            runtimeKind: source.configuration.kind,
            listContext: listContext ?? items.first?.listContext,
            items: items
        )
    }
}
