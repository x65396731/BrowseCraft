import Foundation
import BrowseCraftCore
import BrowseCraftDomain

// 中文注释：SourceRuntimeFactory 是 SourceConfiguration 到领域 runtime 的唯一分发入口。
public struct SourceRuntimeFactory: SourceRuntimeResolving, Sendable {
    private let comicSourceRuntimeFactory: ComicSourceRuntimeFactory
    private let rssSourceRuntimeFactory: RSSSourceRuntimeFactory
    private let videoSourceRuntimeFactory: VideoSourceRuntimeFactory
    private let pluginRuntimeFactory: (@Sendable (Source) throws -> any SourceRuntime)?
    private let validateSourceAccess: (@Sendable (Source) throws -> Void)?

    public init(
        comicSourceRuntimeFactory: ComicSourceRuntimeFactory,
        rssSourceRuntimeFactory: RSSSourceRuntimeFactory,
        videoSourceRuntimeFactory: VideoSourceRuntimeFactory,
        pluginRuntimeFactory: (@Sendable (Source) throws -> any SourceRuntime)? = nil,
        validateSourceAccess: (@Sendable (Source) throws -> Void)? = nil
    ) {
        self.comicSourceRuntimeFactory = comicSourceRuntimeFactory
        self.rssSourceRuntimeFactory = rssSourceRuntimeFactory
        self.videoSourceRuntimeFactory = videoSourceRuntimeFactory
        self.pluginRuntimeFactory = pluginRuntimeFactory
        self.validateSourceAccess = validateSourceAccess
    }

    public func runtime(for source: Source) throws -> any SourceRuntime {
        if let validateSourceAccess: @Sendable (Source) throws -> Void =
            self.validateSourceAccess {
            try validateSourceAccess(source)
        } else {
            // 中文注释：槽位额度是 App 的决策，不属于 runtime 语义；组合根注入 validateSourceAccess
            // 时由它抛出具体错误，这里只表达"该 source 当前不可执行"。
            guard source.accessState == .active else {
                throw SourceRuntimeError.unsupported(
                    .custom("Source \(source.id) is not active.")
                )
            }
        }

        switch source.configuration {
        case .comic:
            return try self.comicSourceRuntimeFactory.makeRuntime(source: source)
        case .rss:
            return try self.rssSourceRuntimeFactory.makeRuntime(source: source)
        case .video:
            return try self.videoSourceRuntimeFactory.makeRuntime(source: source)
        case .plugin:
            guard let pluginRuntimeFactory: @Sendable (Source) throws -> any SourceRuntime = self.pluginRuntimeFactory else {
                throw SourceRuntimeError.unsupported(
                    .custom("Plugin source runtime is not connected in SourceRuntimeFactory.")
                )
            }
            return try pluginRuntimeFactory(source)
        }
    }
}
