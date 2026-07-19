import Foundation
import BrowseCraftCore

// 中文注释：SourceRuntimeFactory 是 SourceConfiguration 到领域 runtime 的唯一分发入口。
struct SourceRuntimeFactory: SourceRuntimeResolving {
    private let comicSourceRuntimeFactory: ComicSourceRuntimeFactory
    private let rssSourceRuntimeFactory: RSSSourceRuntimeFactory
    private let videoSourceRuntimeFactory: VideoSourceRuntimeFactory
    private let pluginRuntimeFactory: ((Source) throws -> any SourceRuntime)?

    init(
        comicSourceRuntimeFactory: ComicSourceRuntimeFactory,
        rssSourceRuntimeFactory: RSSSourceRuntimeFactory,
        videoSourceRuntimeFactory: VideoSourceRuntimeFactory,
        pluginRuntimeFactory: ((Source) throws -> any SourceRuntime)? = nil
    ) {
        self.comicSourceRuntimeFactory = comicSourceRuntimeFactory
        self.rssSourceRuntimeFactory = rssSourceRuntimeFactory
        self.videoSourceRuntimeFactory = videoSourceRuntimeFactory
        self.pluginRuntimeFactory = pluginRuntimeFactory
    }

    func runtime(for source: Source) throws -> any SourceRuntime {
        switch source.configuration {
        case .comic:
            return try self.comicSourceRuntimeFactory.makeRuntime(source: source)
        case .rss:
            return try self.rssSourceRuntimeFactory.makeRuntime(source: source)
        case .video:
            return try self.videoSourceRuntimeFactory.makeRuntime(source: source)
        case .plugin:
            guard let pluginRuntimeFactory: (Source) throws -> any SourceRuntime = self.pluginRuntimeFactory else {
                throw SourceRuntimeError.unsupported(
                    .custom("Plugin source runtime is not connected in SourceRuntimeFactory.")
                )
            }
            return try pluginRuntimeFactory(source)
        }
    }
}
