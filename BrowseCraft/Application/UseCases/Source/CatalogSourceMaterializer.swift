import Foundation
import BrowseCraftCore
import BrowseCraftRulesKit

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
            let videoRule: CatalogVideoRule = try self.decodeRule(CatalogVideoRule.self, from: catalogSource)
            let importedAdapter: VideoAdapter = try self.adapter(from: videoRule.adapter)
            let routePatterns: VideoSourceRoutePatterns? = try self.routePatterns(from: videoRule.routePattern)
            let contentAdapter: VideoAdapter = self.contentAdapter(
                importedAdapter: importedAdapter,
                routePatterns: routePatterns
            )
            let sharedRequest: RequestConfig? = importedAdapter == .webView
                ? self.webViewRequest(videoRule.sharedRequest)
                : videoRule.sharedRequest
            return Source(
                id: catalogSource.id,
                name: catalogSource.name,
                baseURL: catalogSource.baseURL,
                type: .html,
                configuration: .video(
                    VideoSourceConfiguration(
                        definition: VideoSourceDefinition(
                            adapter: contentAdapter,
                            entryURL: try self.url(
                                from: videoRule.entryURL,
                                error: CatalogSourceImportError.invalidEntryURL
                            ),
                            seedURL: nil,
                            entryKind: try self.entryKind(from: videoRule.entryKind),
                            routePatterns: routePatterns,
                            playbackPolicy: try self.playbackPolicy(from: videoRule.playbackPolicy),
                            sharedRequest: sharedRequest,
                            listRequest: videoRule.listRequest,
                            detailRequest: videoRule.detailRequest,
                            playRequest: videoRule.playRequest,
                            requiresAccount: videoRule.requiresAccount,
                            seedVodID: nil,
                            seedSourceIndex: nil,
                            seedEpisodeIndex: nil,
                            seedDetailURL: nil,
                            seedPlayURL: nil
                        ),
                        listTabs: videoRule.listTabs.map(self.listTab(from:))
                    )
                ),
                enabled: enabled,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
    }

    private func contentAdapter(
        importedAdapter: VideoAdapter,
        routePatterns: VideoSourceRoutePatterns?
    ) -> VideoAdapter {
        if importedAdapter == .webView {
            return .genericHTML
        }
        if routePatterns == .macCMS {
            return .macCMS
        }
        return importedAdapter
    }

    private func rule(from catalogSource: BrowseCraftCatalogSource) throws -> SiteRule {
        do {
            return try self.jsonDecoder.decode(SiteRule.self, from: Data(catalogSource.ruleJSON.utf8))
        } catch {
            throw self.invalidRuleJSONError(for: catalogSource, underlyingError: error)
        }
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

    private func adapter(from adapter: String) throws -> VideoAdapter {
        switch adapter {
        case "macCMS":
            return .macCMS
        case "genericHTML":
            return .genericHTML
        case "webView":
            return .webView
        case "plugin":
            throw CatalogSourceImportError.unsupportedRuleValue(field: "adapter", value: adapter)
        default:
            throw CatalogSourceImportError.unsupportedRuleValue(field: "adapter", value: adapter)
        }
    }

    private func entryKind(from entryKind: String) throws -> VideoSourceEntryKind {
        switch entryKind {
        case "home":
            return .home
        case "category":
            return .category
        case "list":
            return .list
        case "detail":
            return .detail
        case "play":
            return .play
        default:
            throw CatalogSourceImportError.unsupportedRuleValue(field: "entryKind", value: entryKind)
        }
    }

    private func routePatterns(from routePattern: CatalogRoutePattern?) throws -> VideoSourceRoutePatterns? {
        if let unsupportedPreset: String = routePattern?.unsupportedPreset {
            throw CatalogSourceImportError.unsupportedRuleValue(field: "routePattern", value: unsupportedPreset)
        }

        switch routePattern?.preset {
        case "macCMS":
            return .macCMS
        case nil:
            return nil
        default:
            return nil
        }
    }

    private func playbackPolicy(from playbackPolicy: String) throws -> VideoPlaybackPolicy {
        switch playbackPolicy {
        case "playPageFirst":
            return .playPageFirst
        default:
            throw CatalogSourceImportError.unsupportedRuleValue(field: "playbackPolicy", value: playbackPolicy)
        }
    }

    private func webViewRequest(_ request: RequestConfig?) -> RequestConfig {
        return RequestConfig(
            scope: request?.scope,
            mergePolicy: request?.mergePolicy,
            method: request?.method,
            headers: request?.headers,
            body: request?.body,
            cookiePolicy: request?.cookiePolicy,
            cookiePriority: request?.cookiePriority,
            cookieScope: request?.cookieScope,
            charset: request?.charset,
            needsWebView: true,
            autoScroll: request?.autoScroll,
            imageHeaders: request?.imageHeaders,
            imageRequest: request?.imageRequest
        )
    }

    private func listTab(from tab: CatalogVideoListTabRule) -> VideoSourceListTab {
        return VideoSourceListTab(
            id: tab.id,
            title: tab.title,
            url: tab.url,
            itemSelector: tab.itemSelector,
            titleSelector: tab.titleSelector,
            linkSelector: tab.linkSelector,
            coverSelector: tab.coverSelector,
            latestTextSelector: tab.latestTextSelector
        )
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

private struct CatalogVideoRule: Decodable {
    let adapter: String
    let entryURL: String
    let entryKind: String
    let routePattern: CatalogRoutePattern?
    let playbackPolicy: String
    let sharedRequest: RequestConfig?
    let listRequest: RequestConfig?
    let detailRequest: RequestConfig?
    let playRequest: RequestConfig?
    let requiresAccount: Bool
    let listTabs: [CatalogVideoListTabRule]

    private enum CodingKeys: String, CodingKey {
        case adapter
        case entryURL
        case entryKind
        case routePattern
        case playbackPolicy
        case sharedRequest
        case listRequest
        case detailRequest
        case playRequest
        case requiresAccount
        case listTabs
    }

    init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        self.adapter = try container.decodeIfPresent(String.self, forKey: .adapter) ?? "genericHTML"
        self.entryURL = try container.decode(String.self, forKey: .entryURL)
        self.entryKind = try container.decodeIfPresent(String.self, forKey: .entryKind) ?? "list"
        self.routePattern = try container.decodeIfPresent(CatalogRoutePattern.self, forKey: .routePattern)
        self.playbackPolicy = try container.decodeIfPresent(String.self, forKey: .playbackPolicy) ?? "playPageFirst"
        self.sharedRequest = try Self.decodeRequest(from: container, forKey: .sharedRequest)
        self.listRequest = try Self.decodeRequest(from: container, forKey: .listRequest)
        self.detailRequest = try Self.decodeRequest(from: container, forKey: .detailRequest)
        self.playRequest = try Self.decodeRequest(from: container, forKey: .playRequest)
        self.requiresAccount = try container.decodeIfPresent(Bool.self, forKey: .requiresAccount) ?? false
        self.listTabs = try container.decodeIfPresent([CatalogVideoListTabRule].self, forKey: .listTabs) ?? []
    }

    private static func decodeRequest(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> RequestConfig? {
        return try container.decodeIfPresent(CatalogRequestConfig.self, forKey: key)?.requestConfig
    }
}

private struct CatalogRoutePattern: Decodable {
    let preset: String?
    private let strictStringPreset: Bool

    private enum CodingKeys: String, CodingKey {
        case adapter
        case category
        case detail
        case kind
        case list
        case macCMS
        case mode
        case name
        case play
        case preset
        case routePattern
        case search
        case type
    }

    init(from decoder: Decoder) throws {
        if let stringValue: String = try? decoder.singleValueContainer().decode(String.self) {
            self.preset = stringValue
            self.strictStringPreset = true
            return
        }

        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        self.preset = try Self.objectPreset(from: container)
        self.strictStringPreset = false
    }

    var unsupportedPreset: String? {
        guard self.strictStringPreset, self.preset != "macCMS" else {
            return nil
        }
        return self.preset
    }

    private static func objectPreset(from container: KeyedDecodingContainer<CodingKeys>) throws -> String? {
        let keys: [CodingKeys] = [.preset, .type, .kind, .name, .adapter, .mode, .routePattern]
        for key in keys {
            if let value: String = try? container.decodeIfPresent(String.self, forKey: key) {
                if self.isMacCMSMarker(value) {
                    return "macCMS"
                }
            }
        }
        if (try container.decodeIfPresent(Bool.self, forKey: .macCMS)) == true {
            return "macCMS"
        }
        if try self.containsMacCMSRouteTemplate(in: container) {
            return "macCMS"
        }
        return nil
    }

    private static func containsMacCMSRouteTemplate(
        in container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Bool {
        let keys: [CodingKeys] = [.detail, .play, .list, .category, .search]
        for key in keys {
            if let value: String = try? container.decodeIfPresent(String.self, forKey: key),
               self.isMacCMSMarker(value) {
                return true
            }
        }
        return false
    }

    private static func isMacCMSMarker(_ value: String) -> Bool {
        let normalized: String = value.lowercased()
        return normalized == "maccms"
            || normalized.contains("/voddetail/")
            || normalized.contains("/vodplay/")
    }
}

private struct CatalogVideoListTabRule: Decodable {
    let id: String
    let title: String
    let url: String
    let itemSelector: String?
    let titleSelector: String?
    let linkSelector: String?
    let coverSelector: String?
    let latestTextSelector: String?
}

private struct CatalogRequestConfig: Decodable {
    let requestConfig: RequestConfig

    private enum CodingKeys: String, CodingKey {
        case scope
        case mergePolicy
        case method
        case headers
        case body
        case cookiePolicy
        case cookiePriority
        case cookieScope
        case charset
        case needsWebView
        case autoScroll
        case imageHeaders
        case imageRequest
    }

    init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        self.requestConfig = RequestConfig(
            scope: try decodeCatalogEnum(RequestScope.self, from: container, forKey: .scope),
            mergePolicy: try decodeCatalogEnum(
                RequestMergePolicy.self,
                from: container,
                forKey: .mergePolicy,
                aliases: ["merge": .mergeHeadersAndCookies]
            ),
            method: try decodeCatalogEnum(HTTPMethod.self, from: container, forKey: .method),
            headers: try container.decodeIfPresent([String: String].self, forKey: .headers),
            body: try container.decodeIfPresent(RequestBody.self, forKey: .body),
            cookiePolicy: try decodeCatalogEnum(CookiePolicy.self, from: container, forKey: .cookiePolicy),
            cookiePriority: try decodeCatalogEnum(CookiePriority.self, from: container, forKey: .cookiePriority),
            cookieScope: try decodeCatalogEnum(
                CookieScope.self,
                from: container,
                forKey: .cookieScope,
                aliases: ["source": .site]
            ),
            charset: try decodeCatalogEnum(
                Charset.self,
                from: container,
                forKey: .charset,
                aliases: [
                    "utf-8": .utf8,
                    "UTF-8": .utf8,
                    "shift-jis": .shiftJIS,
                    "Shift_JIS": .shiftJIS
                ]
            ),
            needsWebView: try container.decodeIfPresent(Bool.self, forKey: .needsWebView),
            autoScroll: try container.decodeIfPresent(Bool.self, forKey: .autoScroll),
            imageHeaders: try container.decodeIfPresent([String: String].self, forKey: .imageHeaders),
            imageRequest: try container.decodeIfPresent(CatalogImageRequestConfig.self, forKey: .imageRequest)?.imageRequestConfig
        )
    }
}

private struct CatalogImageRequestConfig: Decodable {
    let imageRequestConfig: ImageRequestConfig

    private enum CodingKeys: String, CodingKey {
        case headers
        case cookiePolicy
        case cookiePriority
        case cookieScope
        case mergePolicy
    }

    init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        self.imageRequestConfig = ImageRequestConfig(
            headers: try container.decodeIfPresent([String: String].self, forKey: .headers),
            cookiePolicy: try decodeCatalogEnum(CookiePolicy.self, from: container, forKey: .cookiePolicy),
            cookiePriority: try decodeCatalogEnum(CookiePriority.self, from: container, forKey: .cookiePriority),
            cookieScope: try decodeCatalogEnum(
                CookieScope.self,
                from: container,
                forKey: .cookieScope,
                aliases: ["source": .site]
            ),
            mergePolicy: try decodeCatalogEnum(
                RequestMergePolicy.self,
                from: container,
                forKey: .mergePolicy,
                aliases: ["merge": .mergeHeadersAndCookies]
            )
        )
    }
}

private func decodeCatalogEnum<Value, Key>(
    _ valueType: Value.Type,
    from container: KeyedDecodingContainer<Key>,
    forKey key: Key,
    aliases: [String: Value] = [:]
) throws -> Value? where Value: RawRepresentable, Value.RawValue == String, Key: CodingKey {
    guard let rawValue: String = try container.decodeIfPresent(String.self, forKey: key) else {
        return nil
    }

    if rawValue == "default" {
        return nil
    }

    if let aliasedValue: Value = aliases[rawValue] {
        return aliasedValue
    }

    guard let value: Value = Value(rawValue: rawValue) else {
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "Cannot initialize \(valueType) from invalid String value \(rawValue)"
        )
    }

    return value
}
