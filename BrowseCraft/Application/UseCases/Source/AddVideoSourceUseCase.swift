import Foundation
import BrowseCraftCore

struct VideoSourceImportInspection: Hashable {
    var baseURL: URL
    var entryURL: URL
    var seedURL: URL?
    var entryKind: VideoSourceEntryKind
    var sourceName: String?
    var logLines: [String]
}

struct ManualVideoSourceConfigurationDraft: Hashable {
    var adapter: VideoAdapter
    var entryKind: VideoSourceEntryKind
}

struct AddManualVideoSourceResult {
    let source: Source
    let listOutput: SourceListOutput
}

enum AddVideoSourceResult: Hashable {
    case inspected(VideoSourceImportInspection)
    case saved(Source)
    case needsReview(Source, warnings: [String])
    case unavailable(VideoSourceUnavailableReason)
    case pluginRequired(VideoSourcePluginReason)
}

// 中文注释：手动 video source 入口不自动判断 adapter/类型；保存必须使用用户选择的配置并通过列表加载验证。
struct AddVideoSourceUseCase {
    private let sourceRepository: SourceRepository
    private let refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase?
    private let validateSourceListLoadUseCase: ValidateSourceListLoadUseCase
    private let urlResolver: VideoSourceURLResolver
    private let now: () -> Date
    private let makeID: () -> String

    init(
        sourceRepository: SourceRepository,
        refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase? = nil,
        validateSourceListLoadUseCase: ValidateSourceListLoadUseCase = ValidateSourceListLoadUseCase(),
        urlResolver: VideoSourceURLResolver = VideoSourceURLResolver(),
        now: @escaping () -> Date = Date.init,
        makeID: @escaping () -> String = { UUID().uuidString }
    ) {
        self.sourceRepository = sourceRepository
        self.refreshSourceRuntimeUseCase = refreshSourceRuntimeUseCase
        self.validateSourceListLoadUseCase = validateSourceListLoadUseCase
        self.urlResolver = urlResolver
        self.now = now
        self.makeID = makeID
    }

    func execute(
        entryURLString: String,
        name: String? = nil,
        entryHTML: String? = nil,
        headers: [String: String] = [:]
    ) throws -> AddVideoSourceResult {
        return .inspected(
            try self.inspect(
                entryURLString: entryURLString,
                name: name,
                entryHTML: entryHTML,
                headers: headers
            )
        )
    }

    func inspect(
        entryURLString: String,
        name: String? = nil,
        entryHTML: String? = nil,
        headers: [String: String] = [:]
    ) throws -> VideoSourceImportInspection {
        let resolution: VideoSourceURLResolution = try self.urlResolver.resolve(entryURLString)
        let sourceName: String? = name?.trimmedNonEmpty
        let logLines: [String] = self.logLines(
            resolution: resolution,
            sourceName: sourceName,
            entryHTML: entryHTML,
            headers: headers
        )

        return VideoSourceImportInspection(
            baseURL: resolution.baseURL,
            entryURL: resolution.entryURL,
            seedURL: resolution.seedURL,
            entryKind: resolution.entryKind,
            sourceName: sourceName,
            logLines: logLines
        )
    }

    func saveManualVideoSource(
        entryURLString: String,
        name: String? = nil,
        configuration: ManualVideoSourceConfigurationDraft
    ) async throws -> AddManualVideoSourceResult {
        let result: AddManualVideoSourceResult = try await self.validatedManualVideoSource(
            entryURLString: entryURLString,
            name: name,
            configuration: configuration
        )
        let source: Source = result.source
        try self.sourceRepository.saveSource(source)
        return result
    }

    private func validatedManualVideoSource(
        entryURLString: String,
        name: String? = nil,
        configuration: ManualVideoSourceConfigurationDraft
    ) async throws -> AddManualVideoSourceResult {
        guard self.isManualAdapterSupported(configuration.adapter) else {
            throw SourceRuntimeError.unsupported(
                .custom("Plugin video adapter import is closed. Use Generic HTML or MacCMS rules.")
            )
        }

        guard let refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase = self.refreshSourceRuntimeUseCase else {
            throw SourceRuntimeError.unsupported(
                .custom("Manual video source saving requires runtime list validation.")
            )
        }

        let inspection: VideoSourceImportInspection = try self.inspect(
            entryURLString: entryURLString,
            name: name
        )
        let source: Source = self.manualSource(
            inspection: inspection,
            inputName: name,
            configuration: configuration
        )
        let listOutput: SourceListOutput = try await refreshSourceRuntimeUseCase.execute(
            source: source,
            listContext: nil,
            debugMode: false
        )
        try self.validateSourceListLoadUseCase.execute(listOutput)
        return AddManualVideoSourceResult(
            source: source,
            listOutput: listOutput
        )
    }

    private func logLines(
        resolution: VideoSourceURLResolution,
        sourceName: String?,
        entryHTML: String?,
        headers: [String: String]
    ) -> [String] {
        var lines: [String] = [
            "Input accepted.",
            "Base URL: \(resolution.baseURL.absoluteString)",
            "Entry URL: \(resolution.entryURL.absoluteString)",
            "Entry page role: \(self.displayTitle(for: resolution.entryKind))"
        ]

        if let sourceName: String {
            lines.append("Name: \(sourceName)")
        }
        if let seedURL: URL = resolution.seedURL {
            lines.append("Seed URL: \(seedURL.absoluteString)")
        }
        if let vodID: String = resolution.vodID {
            lines.append("Seed vod id: \(vodID)")
        }
        if let sourceIndex: Int = resolution.sourceIndex {
            lines.append("Seed source index: \(sourceIndex)")
        }
        if let episodeIndex: Int = resolution.episodeIndex {
            lines.append("Seed episode index: \(episodeIndex)")
        }

        lines.append("Headers: \(headers.count)")

        if let entryHTML: String {
            lines.append("HTML provided: yes")
            lines.append("HTML bytes: \(entryHTML.utf8.count)")
            lines.append("Contains iframe: \(entryHTML.range(of: "<iframe", options: .caseInsensitive) == nil ? "no" : "yes")")
            lines.append("Contains video tag: \(entryHTML.range(of: "<video", options: .caseInsensitive) == nil ? "no" : "yes")")
        } else {
            lines.append("HTML provided: no")
        }

        lines.append("No video adapter or source type was inferred.")
        return lines
    }

    private func displayTitle(for entryKind: VideoSourceEntryKind) -> String {
        switch entryKind {
        case .home:
            return "home"
        case .category:
            return "category"
        case .list:
            return "list"
        case .detail:
            return "detail"
        case .play:
            return "play"
        }
    }

    private func sourceName(
        inputName: String?,
        inspection: VideoSourceImportInspection
    ) -> String {
        if let inputName: String = inputName?.trimmedNonEmpty {
            return inputName
        }

        return inspection.entryURL.host ?? "Video Source"
    }

    private func manualSource(
        inspection: VideoSourceImportInspection,
        inputName: String?,
        configuration: ManualVideoSourceConfigurationDraft
    ) -> Source {
        let timestamp: Date = self.now()
        return Source(
            id: self.makeID(),
            name: self.sourceName(inputName: inputName, inspection: inspection),
            baseURL: inspection.baseURL.absoluteString,
            type: .html,
            configuration: .video(
                VideoSourceConfiguration(
                    definition: VideoSourceDefinition(
                        adapter: configuration.adapter,
                        entryURL: inspection.entryURL,
                        seedURL: inspection.seedURL,
                        entryKind: configuration.entryKind,
                        routePatterns: configuration.adapter == .macCMS ? .macCMS : nil,
                        playbackPolicy: .playPageFirst,
                        requiresAccount: false,
                        seedVodID: nil,
                        seedSourceIndex: nil,
                        seedEpisodeIndex: nil,
                        seedDetailURL: nil,
                        seedPlayURL: configuration.entryKind == .play ? inspection.entryURL : nil
                    )
                )
            ),
            enabled: true,
            createdAt: timestamp,
            updatedAt: timestamp
        )
    }

    private func isManualAdapterSupported(_ adapter: VideoAdapter) -> Bool {
        switch adapter {
        case .genericHTML, .macCMS:
            return true
        case .webView, .plugin:
            return false
        }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed: String = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
