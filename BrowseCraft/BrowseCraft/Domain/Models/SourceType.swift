import Foundation

/// The raw source format before BrowseCraft parses it into normalized models.
enum SourceType: String, Codable, CaseIterable, Identifiable, Hashable {
    case rss
    case html
    case json
    case xml

    var id: String {
        return self.rawValue
    }
}

