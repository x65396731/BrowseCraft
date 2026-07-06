import Foundation
import BrowseCraftCore

// 中文注释：AddVideoSourceUseCase 保存模板化 video website source；本阶段不抓取页面、不接播放器。
struct AddVideoSourceUseCase {
    private let sourceRepository: SourceRepository
    private let urlResolver: VideoSourceURLResolver
    private let now: () -> Date
    private let makeID: () -> String

    init(
        sourceRepository: SourceRepository,
        urlResolver: VideoSourceURLResolver = VideoSourceURLResolver(),
        now: @escaping () -> Date = Date.init,
        makeID: @escaping () -> String = { UUID().uuidString }
    ) {
        self.sourceRepository = sourceRepository
        self.urlResolver = urlResolver
        self.now = now
        self.makeID = makeID
    }

    func execute(entryURLString: String, name: String? = nil) throws -> Source {
        let resolution: VideoSourceURLResolution = try self.urlResolver.resolve(entryURLString)
        let timestamp: Date = self.now()
        let definition: VideoSourceDefinition = VideoSourceDefinition(
            siteKind: .macCMS,
            entryURL: resolution.entryURL,
            seedURL: resolution.seedURL,
            entryKind: resolution.entryKind,
            routePatterns: .macCMS,
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
            configuration: .video(VideoSourceConfiguration(definition: definition)),
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
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed: String = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
