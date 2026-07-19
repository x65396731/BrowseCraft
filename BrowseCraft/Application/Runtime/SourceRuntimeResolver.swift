import Foundation
import BrowseCraftCore

// 中文注释：SourceRuntimeResolver 只按 SourceDefinition.runtimeKind 分发 runtime，不再按 SourceType 分流。
protocol SourceRuntimeResolving {
    func runtime(for source: Source) throws -> any SourceRuntime
}

struct SourceRuntimeResolver: SourceRuntimeResolving {
    private let definitionMapper: SourceDefinitionMapper
    private let comicRuntimeFactory: (Source) -> any SourceRuntime
    private let rssRuntimeFactory: ((SourceDefinition) -> any SourceRuntime)?
    private let videoRuleRuntimeFactory: ((Source) throws -> any SourceRuntime)?
    private let pluginRuntimeFactory: ((SourceDefinition) -> any SourceRuntime)?

    init(
        definitionMapper: SourceDefinitionMapper = SourceDefinitionMapper(),
        rssRuntimeFactory: ((SourceDefinition) -> any SourceRuntime)? = nil,
        videoRuleRuntimeFactory: ((Source) throws -> any SourceRuntime)? = nil,
        pluginRuntimeFactory: ((SourceDefinition) -> any SourceRuntime)? = nil,
        comicRuntimeFactory: @escaping (Source) -> any SourceRuntime
    ) {
        self.definitionMapper = definitionMapper
        self.comicRuntimeFactory = comicRuntimeFactory
        self.rssRuntimeFactory = rssRuntimeFactory
        self.videoRuleRuntimeFactory = videoRuleRuntimeFactory
        self.pluginRuntimeFactory = pluginRuntimeFactory
    }

    func runtime(for source: Source) throws -> any SourceRuntime {
        let definition: SourceDefinition = self.definitionMapper.definition(from: source)
        return try self.runtime(for: definition, source: source)
    }

    func runtime(for definition: SourceDefinition) throws -> any SourceRuntime {
        return try self.runtime(for: definition, source: nil)
    }

    private func runtime(
        for definition: SourceDefinition,
        source: Source?
    ) throws -> any SourceRuntime {
        switch definition.runtimeKind {
        case .comic:
            guard let source: Source = source else {
                throw SourceRuntimeError.invalidInput("Comic runtime resolution requires an App Source payload.")
            }
            return self.comicRuntimeFactory(source)
        case .rss:
            if let rssRuntimeFactory: (SourceDefinition) -> any SourceRuntime = self.rssRuntimeFactory {
                return rssRuntimeFactory(definition)
            }

            throw SourceRuntimeError.unsupported(
                .custom("RSS source runtime is not connected in this resolver.")
            )
        case .video:
            guard let source: Source else {
                throw SourceRuntimeError.invalidInput(
                    "Video V2 runtime resolution requires the persisted App Source payload."
                )
            }
            guard let videoRuleRuntimeFactory: (Source) throws -> any SourceRuntime = self.videoRuleRuntimeFactory else {
                throw SourceRuntimeError.unsupported(
                    .custom("Video V2 rule-driven runtime is not connected in this resolver.")
                )
            }
            return try videoRuleRuntimeFactory(source)
        case .plugin:
            if let pluginRuntimeFactory: (SourceDefinition) -> any SourceRuntime = self.pluginRuntimeFactory {
                return pluginRuntimeFactory(definition)
            }

            throw SourceRuntimeError.unsupported(
                .custom("Plugin source runtime is not connected in this resolver.")
            )
        }
    }
}
