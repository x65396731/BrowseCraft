import Foundation
import BrowseCraftCore

enum SourceListLoadValidationError: LocalizedError, Equatable {
    case emptyList

    var errorDescription: String? {
        switch self {
        case .emptyList:
            return "The source loaded successfully but returned no items."
        }
    }
}

struct ValidateSourceListLoadUseCase {
    func execute(_ output: SourceListOutput) throws {
        if output.items.isEmpty {
            throw SourceListLoadValidationError.emptyList
        }
    }
}

enum SourceTabValidationStatus: Equatable {
    case valid
    case empty
    case failed(String)
    case skipped(String)
}

struct SourceTabValidationEntry: Equatable, Identifiable {
    let id: String
    let tabID: String?
    let title: String
    let context: ListContext?
    let status: SourceTabValidationStatus
    let itemCount: Int
}

struct SourceTabsValidationResult: Equatable {
    let sourceID: String
    let runtimeKind: SourceRuntimeKind
    let validatedSource: Source
    let entries: [SourceTabValidationEntry]
}

// 中文注释：P5 tab 验证按 source kind 分流；RSS 只验证 feed，不进入 listRule 链路。
struct ValidateSourceTabsUseCase {
    private let refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase
    private let rssFeedLoader: (any RSSFeedLoading)?
    private let videoTabDiscoveryUseCase: VideoSourceTabDiscoveryUseCase?
    private let sourcePresentationResolver: ResolveLibrarySourcePresentationUseCase
    private let validateSourceListLoadUseCase: ValidateSourceListLoadUseCase

    init(
        refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase,
        rssFeedLoader: (any RSSFeedLoading)? = nil,
        videoTabDiscoveryUseCase: VideoSourceTabDiscoveryUseCase? = nil,
        sourcePresentationResolver: ResolveLibrarySourcePresentationUseCase = ResolveLibrarySourcePresentationUseCase(),
        validateSourceListLoadUseCase: ValidateSourceListLoadUseCase = ValidateSourceListLoadUseCase()
    ) {
        self.refreshSourceRuntimeUseCase = refreshSourceRuntimeUseCase
        self.rssFeedLoader = rssFeedLoader
        self.videoTabDiscoveryUseCase = videoTabDiscoveryUseCase
        self.sourcePresentationResolver = sourcePresentationResolver
        self.validateSourceListLoadUseCase = validateSourceListLoadUseCase
    }

    func execute(source: Source) async -> SourceTabsValidationResult {
        switch source.configuration {
        case .comic:
            return await self.validateListRuntimeTabs(source: source)
        case .video:
            return await self.validateVideoTabs(source: source)
        case .rss(let configuration):
            return await self.validateRSSFeed(source: source, configuration: configuration)
        case .plugin:
            return SourceTabsValidationResult(
                sourceID: source.id,
                runtimeKind: source.configuration.kind,
                validatedSource: source,
                entries: [
                    SourceTabValidationEntry(
                        id: "\(source.id)::plugin",
                        tabID: nil,
                        title: source.name,
                        context: nil,
                        status: .skipped("Plugin sources are validated by their plugin runtime."),
                        itemCount: 0
                    )
                ]
            )
        }
    }

    private func validateVideoTabs(source: Source) async -> SourceTabsValidationResult {
        guard case .video(let configuration) = source.configuration else {
            return await self.validateListRuntimeTabs(source: source)
        }

        var validatedSource: Source = source
        if let videoTabDiscoveryUseCase: VideoSourceTabDiscoveryUseCase {
            do {
                let discoveredTabs: [VideoSourceListTab] = try await videoTabDiscoveryUseCase.discoverTabs(
                    sourceID: source.id,
                    definition: configuration.definition,
                    explicitTabs: configuration.listTabs
                )
                if discoveredTabs != configuration.listTabs {
                    validatedSource.configuration = .video(
                        VideoSourceConfiguration(
                            definition: configuration.definition,
                            listTabs: discoveredTabs
                        )
                    )
                }
            } catch {
                #if DEBUG
                print(
                    "[BrowseCraftTabValidation] video discovery failed " +
                    "source=\(source.id) error=\(error)"
                )
                #endif
            }
        }

        return await self.validateListRuntimeTabs(source: validatedSource)
    }

    private func validateListRuntimeTabs(source: Source) async -> SourceTabsValidationResult {
        let tabs: [ListTabRule] = self.sourcePresentationResolver.listTabs(for: source)
        guard tabs.isEmpty == false else {
            return SourceTabsValidationResult(
                sourceID: source.id,
                runtimeKind: source.configuration.kind,
                validatedSource: source,
                entries: [
                    SourceTabValidationEntry(
                        id: "\(source.id)::no-tabs",
                        tabID: nil,
                        title: source.name,
                        context: nil,
                        status: .skipped("No list tabs are available for this source."),
                        itemCount: 0
                    )
                ]
            )
        }

        var entries: [SourceTabValidationEntry] = []
        for tab: ListTabRule in tabs {
            let context: ListContext? = self.sourcePresentationResolver.listContext(from: tab)
            let entryID: String = "\(source.id)::\(tab.id)"

            do {
                let output: SourceListOutput = try await self.refreshSourceRuntimeUseCase.execute(
                    source: source,
                    listContext: context
                )
                do {
                    try self.validateSourceListLoadUseCase.execute(output)
                    entries.append(
                        SourceTabValidationEntry(
                            id: entryID,
                            tabID: tab.id,
                            title: tab.title,
                            context: context,
                            status: .valid,
                            itemCount: output.items.count
                        )
                    )
                } catch SourceListLoadValidationError.emptyList {
                    entries.append(
                        SourceTabValidationEntry(
                            id: entryID,
                            tabID: tab.id,
                            title: tab.title,
                            context: context,
                            status: .empty,
                            itemCount: output.items.count
                        )
                    )
                } catch {
                    entries.append(self.failedEntry(source: source, tab: tab, context: context, error: error))
                }
            } catch {
                entries.append(self.failedEntry(source: source, tab: tab, context: context, error: error))
            }
        }

        return SourceTabsValidationResult(
            sourceID: source.id,
            runtimeKind: source.configuration.kind,
            validatedSource: source,
            entries: entries
        )
    }

    private func validateRSSFeed(
        source: Source,
        configuration: RSSSourceConfiguration
    ) async -> SourceTabsValidationResult {
        guard let rssFeedLoader = self.rssFeedLoader else {
            return self.rssResult(
                source: source,
                status: .skipped("RSS feed loader is unavailable."),
                itemCount: 0
            )
        }

        do {
            let feed: RSSFeed = try await rssFeedLoader.load(feedURL: configuration.definition.feedURL)
            return self.rssResult(
                source: source,
                status: feed.items.isEmpty ? .empty : .valid,
                itemCount: feed.items.count
            )
        } catch {
            return self.rssResult(
                source: source,
                status: .failed(RuleExecutionErrorClassifier.userMessage(for: error)),
                itemCount: 0
            )
        }
    }

    private func rssResult(
        source: Source,
        status: SourceTabValidationStatus,
        itemCount: Int
    ) -> SourceTabsValidationResult {
        return SourceTabsValidationResult(
            sourceID: source.id,
            runtimeKind: source.configuration.kind,
            validatedSource: source,
            entries: [
                SourceTabValidationEntry(
                    id: "\(source.id)::rss-feed",
                    tabID: nil,
                    title: source.name,
                    context: nil,
                    status: status,
                    itemCount: itemCount
                )
            ]
        )
    }

    private func failedEntry(
        source: Source,
        tab: ListTabRule,
        context: ListContext?,
        error: Error
    ) -> SourceTabValidationEntry {
        return SourceTabValidationEntry(
            id: "\(source.id)::\(tab.id)",
            tabID: tab.id,
            title: tab.title,
            context: context,
            status: .failed(RuleExecutionErrorClassifier.userMessage(for: error)),
            itemCount: 0
        )
    }
}
