import Foundation
import BrowseCraftCore

// 中文注释：AddVideoSourceUseCase 保存模板化 video website source；本阶段不抓取页面、不接播放器。
struct AddVideoSourceUseCase {
    private let sourceRepository: SourceRepository
    private let urlResolver: VideoSourceURLResolver
    private let adapterDetector: any VideoAdapterDetecting
    private let tabDiscovererRegistry: VideoTabDiscovererRegistry
    private let now: () -> Date
    private let makeID: () -> String

    init(
        sourceRepository: SourceRepository,
        urlResolver: VideoSourceURLResolver = VideoSourceURLResolver(),
        adapterDetector: any VideoAdapterDetecting = VideoAdapterDetector(),
        tabDiscovererRegistry: VideoTabDiscovererRegistry = VideoTabDiscovererRegistry(),
        now: @escaping () -> Date = Date.init,
        makeID: @escaping () -> String = { UUID().uuidString }
    ) {
        self.sourceRepository = sourceRepository
        self.urlResolver = urlResolver
        self.adapterDetector = adapterDetector
        self.tabDiscovererRegistry = tabDiscovererRegistry
        self.now = now
        self.makeID = makeID
    }

    func execute(
        entryURLString: String,
        name: String? = nil,
        entryHTML: String? = nil,
        headers: [String: String] = [:]
    ) throws -> Source {
        let resolution: VideoSourceURLResolution = try self.urlResolver.resolve(entryURLString)
        let timestamp: Date = self.now()
        let adapter: VideoAdapter = self.adapter(
            entryURL: resolution.entryURL,
            html: entryHTML,
            headers: headers
        )
        let definition: VideoSourceDefinition = VideoSourceDefinition(
            adapter: adapter,
            entryURL: resolution.entryURL,
            seedURL: resolution.seedURL,
            entryKind: resolution.entryKind,
            routePatterns: adapter == .macCMS ? .macCMS : nil,
            playbackPolicy: .playPageFirst,
            requiresAccount: false,
            seedVodID: resolution.vodID,
            seedSourceIndex: resolution.sourceIndex,
            seedEpisodeIndex: resolution.episodeIndex,
            seedDetailURL: resolution.seedDetailURL,
            seedPlayURL: resolution.seedPlayURL
        )
        let source: Source = Source(
            id: self.makeID(),
            name: self.sourceName(inputName: name, baseURL: resolution.baseURL),
            baseURL: resolution.baseURL.absoluteString,
            type: .html,
            configuration: .video(
                VideoSourceConfiguration(
                    definition: definition,
                    listTabs: try self.listTabs(
                        definition: definition,
                        entryHTML: entryHTML,
                        entryURL: resolution.entryURL
                    )
                )
            ),
            enabled: true,
            createdAt: timestamp,
            updatedAt: timestamp
        )

        try self.sourceRepository.saveSource(source)
        return source
    }

    private func sourceName(inputName: String?, baseURL: URL) -> String {
        if let inputName: String = inputName?.trimmedNonEmpty {
            return inputName
        }

        return baseURL.host ?? "Video Source"
    }

    private func adapter(
        entryURL: URL,
        html: String?,
        headers: [String: String]
    ) -> VideoAdapter {
        guard let html: String else {
            return .macCMS
        }

        let detection: VideoAdapterDetection = self.adapterDetector.detect(
            VideoAdapterDetectionInput(
                url: entryURL,
                html: html,
                headers: headers
            )
        )
        return detection.adapter
    }

    private func listTabs(
        definition: VideoSourceDefinition,
        entryHTML: String?,
        entryURL: URL
    ) throws -> [VideoSourceListTab] {
        guard let entryHTML: String else {
            return [
                VideoTabDiscoveryDefaults.homeTab(for: definition)
            ]
        }

        let discoverer: any VideoTabDiscovering = self.tabDiscovererRegistry.discoverer(
            for: definition.adapter
        )
        return try discoverer.discoverTabs(
            html: entryHTML,
            definition: definition,
            pageURL: entryURL
        )
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed: String = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
