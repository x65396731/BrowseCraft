import Foundation
import BrowseCraftCore
import BrowseCraftAPIKit

// 中文注释：CatalogSourceMaterializer 把 RulesKit catalog 定义转换成 App 持久化 Source。
struct CatalogSourceMaterializer {
    private let jsonDecoder: JSONDecoder

    init(jsonDecoder: JSONDecoder = JSONDecoder()) {
        self.jsonDecoder = jsonDecoder
    }

    func source(
        from catalogSource: BrowseCraftCatalogSource,
        createdAt: Date,
        updatedAt: Date,
        enabled: Bool = true
    ) throws -> Source {
        guard URL(string: catalogSource.baseURL) != nil else {
            throw CatalogSourceImportError.invalidBaseURL(catalogSource.baseURL)
        }

        switch catalogSource.kind {
        case .comic:
            return Source(
                id: catalogSource.id,
                name: catalogSource.name,
                baseURL: catalogSource.baseURL,
                type: .html,
                rule: try self.rule(from: catalogSource),
                enabled: enabled,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        case .rss:
            let rssRule: CatalogRSSRule = try self.decodeRule(CatalogRSSRule.self, from: catalogSource)
            return Source(
                id: catalogSource.id,
                name: catalogSource.name,
                baseURL: catalogSource.baseURL,
                type: .rss,
                configuration: .rss(
                    RSSSourceConfiguration(
                        definition: RSSSourceDefinition(
                            feedURL: try self.url(
                                from: rssRule.feedURL,
                                error: CatalogSourceImportError.invalidFeedURL
                            ),
                            requiresAccount: rssRule.requiresAccount,
                            refreshPolicy: try self.refreshPolicy(from: rssRule.refreshPolicy)
                        )
                    )
                ),
                enabled: enabled,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        case .video:
            return Source(
                id: catalogSource.id,
                name: catalogSource.name,
                baseURL: catalogSource.baseURL,
                type: .html,
                configuration: .video(try self.videoConfiguration(from: catalogSource)),
                enabled: enabled,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
    }

    /// 中文注释：P2-6 后所有 video catalog 都必须通过 V2 合同；缺失或非 2 的版本直接拒绝。
    private func videoConfiguration(
        from catalogSource: BrowseCraftCatalogSource
    ) throws -> VideoSourceConfiguration {
        let validator: VideoSiteRuleValidator = VideoSiteRuleValidator(jsonDecoder: self.jsonDecoder)
        let result: VideoSiteRuleValidationResult = validator.validate(
            ruleJSON: catalogSource.ruleJSON,
            catalogMetadata: VideoSiteRuleCatalogMetadata(
                name: catalogSource.name,
                baseURL: catalogSource.baseURL
            )
        )
        guard result.canImport,
              let rule: VideoSiteRule = result.rule else {
            throw CatalogSourceImportError.invalidRuleJSON(
                sourceID: catalogSource.id,
                name: catalogSource.name,
                kind: catalogSource.kind.rawValue,
                reason: self.videoValidationDescription(result)
            )
        }
        return VideoSourceConfiguration(rule: rule)
    }

    private func videoValidationDescription(_ result: VideoSiteRuleValidationResult) -> String {
        let descriptions: [String] = result.errors.prefix(8).map { issue in
            return "\(issue.path): \(issue.message)"
        }
        return descriptions.isEmpty
            ? "Video V2 validation failed without a resolved rule graph."
            : descriptions.joined(separator: " | ")
    }

    private func rule(from catalogSource: BrowseCraftCatalogSource) throws -> SiteRule {
        do {
            return try self.jsonDecoder.decode(
                SiteRule.self,
                from: self.sanitizedRuleJSONData(from: catalogSource.ruleJSON)
            )
        } catch {
            throw self.invalidRuleJSONError(for: catalogSource, underlyingError: error)
        }
    }

    private func sanitizedRuleJSONData(from ruleJSON: String) -> Data {
        let data: Data = Data(ruleJSON.utf8)
        guard let jsonObject: Any = try? JSONSerialization.jsonObject(with: data) else {
            return data
        }

        var didRemoveEmptyBody: Bool = false
        let sanitizedObject: Any = Self.removingEmptyRequestBodies(
            from: jsonObject,
            didRemoveEmptyBody: &didRemoveEmptyBody
        )
        guard didRemoveEmptyBody,
              JSONSerialization.isValidJSONObject(sanitizedObject),
              let sanitizedData: Data = try? JSONSerialization.data(
                withJSONObject: sanitizedObject,
                options: [.sortedKeys]
              ) else {
            return data
        }

        return sanitizedData
    }

    private static func removingEmptyRequestBodies(
        from value: Any,
        didRemoveEmptyBody: inout Bool
    ) -> Any {
        if var dictionary: [String: Any] = value as? [String: Any] {
            if let body: Any = dictionary["body"],
               self.isEmptyRequestBody(body) {
                dictionary.removeValue(forKey: "body")
                didRemoveEmptyBody = true
            }

            for (key, childValue) in dictionary {
                dictionary[key] = self.removingEmptyRequestBodies(
                    from: childValue,
                    didRemoveEmptyBody: &didRemoveEmptyBody
                )
            }

            return dictionary
        }

        if let array: [Any] = value as? [Any] {
            return array.map { childValue in
                self.removingEmptyRequestBodies(
                    from: childValue,
                    didRemoveEmptyBody: &didRemoveEmptyBody
                )
            }
        }

        return value
    }

    private static func isEmptyRequestBody(_ value: Any) -> Bool {
        if value is NSNull {
            return true
        }

        if let string: String = value as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        guard let dictionary: [String: Any] = value as? [String: Any] else {
            return false
        }

        guard let rawValue: Any = dictionary["value"] else {
            return true
        }

        if rawValue is NSNull {
            return true
        }

        if let string: String = rawValue as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return false
    }

    private func decodeRule<Value: Decodable>(
        _ valueType: Value.Type,
        from catalogSource: BrowseCraftCatalogSource
    ) throws -> Value {
        do {
            return try self.jsonDecoder.decode(valueType, from: Data(catalogSource.ruleJSON.utf8))
        } catch {
            throw self.invalidRuleJSONError(for: catalogSource, underlyingError: error)
        }
    }

    private func invalidRuleJSONError(
        for catalogSource: BrowseCraftCatalogSource,
        underlyingError: Error
    ) -> CatalogSourceImportError {
        return .invalidRuleJSON(
            sourceID: catalogSource.id,
            name: catalogSource.name,
            kind: catalogSource.kind.rawValue,
            reason: Self.decodingDescription(for: underlyingError)
        )
    }

    private static func decodingDescription(for error: Error) -> String {
        if let decodingError: DecodingError = error as? DecodingError {
            switch decodingError {
            case .typeMismatch(let type, let context):
                return "typeMismatch type=\(type) path=\(Self.codingPathDescription(context.codingPath)) detail=\(context.debugDescription)"
            case .valueNotFound(let type, let context):
                return "valueNotFound type=\(type) path=\(Self.codingPathDescription(context.codingPath)) detail=\(context.debugDescription)"
            case .keyNotFound(let key, let context):
                let path: [CodingKey] = context.codingPath + [key]
                return "keyNotFound path=\(Self.codingPathDescription(path)) detail=\(context.debugDescription)"
            case .dataCorrupted(let context):
                return "dataCorrupted path=\(Self.codingPathDescription(context.codingPath)) detail=\(context.debugDescription)"
            @unknown default:
                return decodingError.localizedDescription
            }
        }

        return error.localizedDescription
    }

    private static func codingPathDescription(_ codingPath: [CodingKey]) -> String {
        guard codingPath.isEmpty == false else {
            return "<root>"
        }

        return codingPath.map(\.stringValue).joined(separator: ".")
    }

    private func url(
        from urlString: String,
        error: (String) -> CatalogSourceImportError
    ) throws -> URL {
        guard let url: URL = URL(string: urlString) else {
            throw error(urlString)
        }

        return url
    }

    private func refreshPolicy(from refreshPolicy: String) throws -> SourceRefreshPolicy {
        switch refreshPolicy {
        case "manual":
            return .manual
        case "periodic":
            return .periodic
        default:
            throw CatalogSourceImportError.unsupportedRuleValue(field: "refreshPolicy", value: refreshPolicy)
        }
    }

}

private struct CatalogRSSRule: Decodable {
    let feedURL: String
    let requiresAccount: Bool
    let refreshPolicy: String

    private enum CodingKeys: String, CodingKey {
        case feedURL
        case requiresAccount
        case refreshPolicy
    }

    init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        self.feedURL = try container.decode(String.self, forKey: .feedURL)
        self.requiresAccount = try container.decodeIfPresent(Bool.self, forKey: .requiresAccount) ?? false
        self.refreshPolicy = try container.decodeIfPresent(String.self, forKey: .refreshPolicy) ?? "manual"
    }
}
