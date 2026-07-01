import Foundation

/// A normalized item that BrowseCraft can show in Library.
///
/// The original source can be a web page, RSS item, JSON object, or XML node.
/// After parsing, the UI only needs this unified model.
struct ContentItem: Identifiable, Hashable {
    var id: String
    var sourceId: String
    var title: String
    var detailURL: String
    var coverURL: String?
    var type: ContentType
    var latestText: String?
    var updatedAt: Date?
}

