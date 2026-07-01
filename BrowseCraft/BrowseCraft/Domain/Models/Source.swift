import Foundation

/// A user-added content source.
///
/// A Source owns a SiteRule. The rule tells the parser how to find list items,
/// titles, covers, chapters, images, and videos for this source.
struct Source: Identifiable, Hashable {
    var id: String
    var name: String
    var baseURL: String
    var type: SourceType
    var rule: SiteRule
    var enabled: Bool
    var createdAt: Date
    var updatedAt: Date
}

