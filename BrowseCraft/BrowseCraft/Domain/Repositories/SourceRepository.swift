import Foundation

/// Domain-facing storage API for sources.
///
/// The protocol hides GRDB from the rest of the app. Tests can replace it with
/// a fake repository without creating a real SQLite database.
protocol SourceRepository {
    func fetchSources() throws -> [Source]
    func saveSource(_ source: Source) throws
}

