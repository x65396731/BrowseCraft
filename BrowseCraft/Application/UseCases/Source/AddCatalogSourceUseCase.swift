import Foundation
import BrowseCraftCore
import BrowseCraftRulesKit

enum CatalogSourceImportError: LocalizedError {
    case invalidBaseURL(String)
    case invalidFeedURL(String)
    case invalidEntryURL(String)
    case invalidRuleJSON
    case unsupportedRuleValue(field: String, value: String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let urlString):
            return "Invalid source base URL: \(urlString)."
        case .invalidFeedURL(let urlString):
            return "Invalid RSS feed URL: \(urlString)."
        case .invalidEntryURL(let urlString):
            return "Invalid video entry URL: \(urlString)."
        case .invalidRuleJSON:
            return "Invalid website rule JSON."
        case .unsupportedRuleValue(let field, let value):
            return "Unsupported catalog rule value \(field)=\(value)."
        }
    }
}

struct AddCatalogSourceResult {
    let source: Source
    let listOutput: SourceListOutput?
}

// 中文注释：Catalog 来源必须先通过既存 runtime 加载流程，加载成功后才写入本地 DB。
struct AddCatalogSourceUseCase {
    private let sourceRepository: SourceRepository
    private let refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase
    private let validateSourceListLoadUseCase: ValidateSourceListLoadUseCase
    private let jsonDecoder: JSONDecoder
    private let now: () -> Date

    init(
        sourceRepository: SourceRepository,
        refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase,
        validateSourceListLoadUseCase: ValidateSourceListLoadUseCase = ValidateSourceListLoadUseCase(),
        jsonDecoder: JSONDecoder = JSONDecoder(),
        now: @escaping () -> Date = Date.init
    ) {
        self.sourceRepository = sourceRepository
        self.refreshSourceRuntimeUseCase = refreshSourceRuntimeUseCase
        self.validateSourceListLoadUseCase = validateSourceListLoadUseCase
        self.jsonDecoder = jsonDecoder
        self.now = now
    }

    func execute(_ catalogSource: BrowseCraftCatalogSource) async throws -> AddCatalogSourceResult {
        if let existingSource: Source = try self.sourceRepository.fetchSources().first(where: { source in
            return source.id == catalogSource.id
        }) {
            return AddCatalogSourceResult(source: existingSource, listOutput: nil)
        }

        let source: Source = try self.source(from: catalogSource)
        let listOutput: SourceListOutput = try await self.refreshSourceRuntimeUseCase.execute(
            source: source,
            listContext: nil
        )
        try self.validateSourceListLoadUseCase.execute(listOutput)
        try self.sourceRepository.saveSource(source)
        return AddCatalogSourceResult(source: source, listOutput: listOutput)
    }

    private func source(from catalogSource: BrowseCraftCatalogSource) throws -> Source {
        let createdAt: Date = self.now()

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
                enabled: true,
                createdAt: createdAt,
                updatedAt: createdAt
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
                enabled: true,
                createdAt: createdAt,
                updatedAt: createdAt
            )
        case .video:
            let videoRule: CatalogVideoRule = try self.decodeRule(CatalogVideoRule.self, from: catalogSource.ruleJSON)
            let entryURL: URL = try self.url(
                from: videoRule.entryURL,
                error: CatalogSourceImportError.invalidEntryURL
            )
            return Source(
                id: catalogSource.id,
                name: catalogSource.name,
                baseURL: catalogSource.baseURL,
                type: .html,
                configuration: .video(
                    VideoSourceConfiguration(
                        definition: VideoSourceDefinition(
                            adapter: try self.adapter(from: videoRule.adapter),
                            entryURL: entryURL,
                            seedURL: nil,
                            entryKind: try self.entryKind(from: videoRule.entryKind),
                            routePatterns: try self.routePatterns(from: videoRule.routePattern),
                            playbackPolicy: try self.playbackPolicy(from: videoRule.playbackPolicy),
                            sharedRequest: videoRule.sharedRequest,
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
                enabled: true,
                createdAt: createdAt,
                updatedAt: createdAt
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

    private func refreshPolicy(
        from refreshPolicy: String
    ) throws -> SourceRefreshPolicy {
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
        case "iframe":
            return .iframe
        case "webView":
            return .webView
        case "plugin":
            return .plugin
        default:
            throw CatalogSourceImportError.unsupportedRuleValue(field: "adapter", value: adapter)
        }
    }

    private func entryKind(
        from entryKind: String
    ) throws -> VideoSourceEntryKind {
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

    private func routePatterns(
        from routePattern: String?
    ) throws -> VideoSourceRoutePatterns? {
        switch routePattern {
        case "macCMS":
            return .macCMS
        case nil:
            return nil
        case let value?:
            throw CatalogSourceImportError.unsupportedRuleValue(field: "routePattern", value: value)
        }
    }

    private func playbackPolicy(
        from playbackPolicy: String
    ) throws -> VideoPlaybackPolicy {
        switch playbackPolicy {
        case "playPageFirst":
            return .playPageFirst
        default:
            throw CatalogSourceImportError.unsupportedRuleValue(field: "playbackPolicy", value: playbackPolicy)
        }
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
