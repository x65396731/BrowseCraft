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
                rule: try self.rule(from: catalogSource.ruleJSON),
                enabled: enabled,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        case .rss:
            let rssRule: CatalogRSSRule = try self.decodeRule(CatalogRSSRule.self, from: catalogSource.ruleJSON)
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
            let videoRule: CatalogVideoRule = try self.decodeRule(CatalogVideoRule.self, from: catalogSource.ruleJSON)
            let importedAdapter: VideoAdapter = try self.adapter(from: videoRule.adapter)
            let contentAdapter: VideoAdapter = importedAdapter == .webView ? .genericHTML : importedAdapter
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
                            routePatterns: try self.routePatterns(from: videoRule.routePattern),
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

    private func rule(from ruleJSON: String) throws -> SiteRule {
        do {
            return try self.jsonDecoder.decode(SiteRule.self, from: Data(ruleJSON.utf8))
        } catch {
            throw CatalogSourceImportError.invalidRuleJSON
        }
    }

    private func decodeRule<Value: Decodable>(
        _ valueType: Value.Type,
        from ruleJSON: String
    ) throws -> Value {
        do {
            return try self.jsonDecoder.decode(valueType, from: Data(ruleJSON.utf8))
        } catch {
            throw CatalogSourceImportError.invalidRuleJSON
        }
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

    private func routePatterns(from routePattern: String?) throws -> VideoSourceRoutePatterns? {
        switch routePattern {
        case "macCMS":
            return .macCMS
        case nil:
            return nil
        case let value?:
            throw CatalogSourceImportError.unsupportedRuleValue(field: "routePattern", value: value)
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
}

private struct CatalogVideoRule: Decodable {
    let adapter: String
    let entryURL: String
    let entryKind: String
    let routePattern: String?
    let playbackPolicy: String
    let sharedRequest: RequestConfig?
    let listRequest: RequestConfig?
    let detailRequest: RequestConfig?
    let playRequest: RequestConfig?
    let requiresAccount: Bool
    let listTabs: [CatalogVideoListTabRule]
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
