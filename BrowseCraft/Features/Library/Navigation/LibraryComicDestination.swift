import Foundation

struct LibraryComicDestination: Identifiable, Hashable {
    let item: ContentItem
    let source: Source

    var id: String {
        return [
            self.source.id,
            self.item.id,
            self.item.detailURL
        ].joined(separator: "|")
    }
}
