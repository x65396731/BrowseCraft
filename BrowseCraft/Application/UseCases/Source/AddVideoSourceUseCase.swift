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

enum AddVideoSourceResult: Hashable {
    case inspected(VideoSourceImportInspection)
    case saved(Source)
    case needsReview(Source, warnings: [String])
    case unavailable(VideoSourceUnavailableReason)
    case pluginRequired(VideoSourcePluginReason)
}

struct AddVideoSourceDebugResult: Hashable {
    var result: AddVideoSourceResult
    var debugSnapshot: SourceDebugSnapshot?
}

// 中文注释：手动 video source 入口只做 URL 解析和事实日志，不自动判断 adapter/类型，也不保存 Source。
struct AddVideoSourceUseCase {
    private let urlResolver: VideoSourceURLResolver

    init(
        sourceRepository: SourceRepository,
        urlResolver: VideoSourceURLResolver = VideoSourceURLResolver()
    ) {
        _ = sourceRepository
        self.urlResolver = urlResolver
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

    func executeWithDebugSnapshot(
        entryURLString: String,
        name: String? = nil,
        entryHTML: String? = nil,
        headers: [String: String] = [:]
    ) throws -> AddVideoSourceDebugResult {
        return AddVideoSourceDebugResult(
            result: try self.execute(
                entryURLString: entryURLString,
                name: name,
                entryHTML: entryHTML,
                headers: headers
            ),
            debugSnapshot: nil
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
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed: String = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
