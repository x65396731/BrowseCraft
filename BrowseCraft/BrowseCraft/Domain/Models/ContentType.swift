import Foundation

/// The normalized content kinds that BrowseCraft can display.
///
/// A source website can be HTML, RSS, JSON, or XML, but after parsing we convert
/// every item into one of these app-level content types.
enum ContentType: String, Codable, CaseIterable, Identifiable, Hashable {
    case comic
    case video
    case article
    case gallery

    var id: String {
        return self.rawValue
    }
}

