import Combine
import Foundation

struct SourceLoadingState: Equatable {
    let sourceID: String
    let sourceName: String
    let sourceType: SourceType
}

struct SourceLibrarySnapshot: Equatable {
    let sourceID: String
    let sourceName: String
    let sourceType: SourceType
    let items: [ContentItem]
}

// 中文注释：SourceSelectionStore 是应用级状态服务，只负责记录当前选中的内容源。
final class SourceSelectionStore: ObservableObject {
    @Published var selectedSourceID: String?
    @Published var preparingSource: SourceLoadingState?
    @Published var preparedLibrarySnapshot: SourceLibrarySnapshot?

    func beginPreparingSource(_ source: Source) {
        self.preparingSource = SourceLoadingState(
            sourceID: source.id,
            sourceName: source.name,
            sourceType: source.type
        )
    }

    func endPreparingSource(id sourceID: String) {
        if self.preparingSource?.sourceID == sourceID {
            self.preparingSource = nil
        }
    }

    func publishLibrarySnapshot(source: Source, items: [ContentItem]) {
        self.preparedLibrarySnapshot = SourceLibrarySnapshot(
            sourceID: source.id,
            sourceName: source.name,
            sourceType: source.type,
            items: items
        )
    }
}
