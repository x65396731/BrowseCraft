import Foundation

/// Converts raw source documents into normalized ContentItem values.
///
/// The production implementation currently uses SwiftSoup for HTML, but this
/// protocol keeps the parser replaceable.
protocol RuleParsingService {
    func parseList(html: String, source: Source) throws -> [ContentItem]
}

