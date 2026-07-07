import Foundation
import BrowseCraftCore

enum AddVideoSourceResult: Hashable {
    case saved(Source)
    case needsReview(Source, warnings: [String])
    case unavailable(VideoSourceUnavailableReason)
    case pluginRequired(VideoSourcePluginReason)
}

// 中文注释：AddVideoSourceUseCase 保存模板化 video website source；本阶段不抓取页面、不接播放器。
struct AddVideoSourceUseCase {
    private let sourceRepository: SourceRepository
    private let urlResolver: VideoSourceURLResolver
    private let sourceDetector: any VideoSourceDetecting
    private let decisionResolver: VideoSourceImportDecisionResolver
    private let tabDiscovererRegistry: VideoTabDiscovererRegistry
    private let now: () -> Date
    private let makeID: () -> String

    init(
        sourceRepository: SourceRepository,
        urlResolver: VideoSourceURLResolver = VideoSourceURLResolver(),
        sourceDetector: any VideoSourceDetecting = VideoSourceDetector(),
        decisionResolver: VideoSourceImportDecisionResolver = VideoSourceImportDecisionResolver(),
        tabDiscovererRegistry: VideoTabDiscovererRegistry = VideoTabDiscovererRegistry(),
        now: @escaping () -> Date = Date.init,
        makeID: @escaping () -> String = { UUID().uuidString }
    ) {
        self.sourceRepository = sourceRepository
        self.urlResolver = urlResolver
        self.sourceDetector = sourceDetector
        self.decisionResolver = decisionResolver
        self.tabDiscovererRegistry = tabDiscovererRegistry
        self.now = now
        self.makeID = makeID
    }

    func execute(
        entryURLString: String,
        name: String? = nil,
        entryHTML: String? = nil,
        headers: [String: String] = [:]
    ) throws -> AddVideoSourceResult {
        let resolution: VideoSourceURLResolution = try self.urlResolver.resolve(entryURLString)
        let timestamp: Date = self.now()
        let detection: VideoSourceDetection? = self.detection(
            entryURL: resolution.entryURL,
            html: entryHTML,
            headers: headers
        )
        let adapter: VideoAdapter = detection?.adapter ?? .macCMS
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
        let source: Source = try self.makeSource(
            resolution: resolution,
            definition: definition,
            inputName: name,
            entryHTML: entryHTML,
            timestamp: timestamp
        )

        guard let detection: VideoSourceDetection else {
            return .needsReview(
                source,
                warnings: ["Entry HTML was not provided; review before saving this video source."]
            )
        }

        switch self.decisionResolver.decision(for: detection, definition: definition) {
        case .supported:
            try self.sourceRepository.saveSource(source)
            return .saved(source)
        case .needsReview(_, let warnings):
            return .needsReview(source, warnings: warnings)
        case .unavailable(let reason):
            return .unavailable(reason)
        case .pluginRequired(let reason):
            return .pluginRequired(reason)
        }
    }

    func saveReviewedSource(_ source: Source) throws -> Source {
        try self.sourceRepository.saveSource(source)
        return source
    }

    private func makeSource(
        resolution: VideoSourceURLResolution,
        definition: VideoSourceDefinition,
        inputName: String?,
        entryHTML: String?,
        timestamp: Date
    ) throws -> Source {
        return Source(
            id: self.makeID(),
            name: self.sourceName(inputName: inputName, baseURL: resolution.baseURL),
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
    }

    private func sourceName(inputName: String?, baseURL: URL) -> String {
        if let inputName: String = inputName?.trimmedNonEmpty {
            return inputName
        }

        return baseURL.host ?? "Video Source"
    }

    private func detection(
        entryURL: URL,
        html: String?,
        headers: [String: String]
    ) -> VideoSourceDetection? {
        guard let html: String else {
            return nil
        }

        return self.sourceDetector.detect(
            VideoSourceDetectionInput(
                url: entryURL,
                html: html,
                headers: headers
            )
        )
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
