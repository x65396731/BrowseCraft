import Foundation

/// Reading progress for comics, galleries, and articles.
///
/// Video progress is intentionally modeled separately later because videos need
/// currentTime and duration instead of a page index.
struct ReadingHistory: Identifiable, Hashable {
    var id: String {
        return self.itemId
    }

    var itemId: String
    var chapterId: String?
    var pageIndex: Int
    var updatedAt: Date
}

