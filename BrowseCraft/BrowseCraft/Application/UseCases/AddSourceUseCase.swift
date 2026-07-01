import Foundation

/// Adds a new source from a JSON rule.
///
/// This use case owns the business action "create a Source". It does not know
/// how the source is stored; it only talks to SourceRepository.
struct AddSourceUseCase {
    private let sourceRepository: SourceRepository
    private let jsonDecoder: JSONDecoder

    init(sourceRepository: SourceRepository, jsonDecoder: JSONDecoder = JSONDecoder()) {
        self.sourceRepository = sourceRepository
        self.jsonDecoder = jsonDecoder
    }

    func execute(name: String, baseURL: String, ruleJSON: String) throws -> Source {
        let ruleData: Data = Data(ruleJSON.utf8)
        let rule: SiteRule = try self.jsonDecoder.decode(SiteRule.self, from: ruleData)
        let now: Date = Date()

        let sourceName: String
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sourceName = rule.name
        } else {
            sourceName = name
        }

        let sourceBaseURL: String
        if baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sourceBaseURL = rule.baseUrl
        } else {
            sourceBaseURL = baseURL
        }

        let source: Source = Source(
            id: UUID().uuidString,
            name: sourceName,
            baseURL: sourceBaseURL,
            type: .html,
            rule: rule,
            enabled: true,
            createdAt: now,
            updatedAt: now
        )

        try self.sourceRepository.saveSource(source)
        return source
    }
}

