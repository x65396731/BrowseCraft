import Foundation
import BrowseCraftCore
@testable import BrowseCraft

// 中文注释：测试专用闭包 resolver，避免生产 Runtime 为测试注入保留第二套分发实现。
struct TestSourceRuntimeResolver: SourceRuntimeResolving {
    private let definitionMapper: SourceDefinitionMapper
    private let comicRuntimeFactory: (Source) -> any SourceRuntime
    private let rssRuntimeFactory: ((SourceDefinition) -> any SourceRuntime)?
    private let videoRuntimeFactory: ((Source) throws -> any SourceRuntime)?
    private let pluginRuntimeFactory: ((SourceDefinition) -> any SourceRuntime)?

    init(
        definitionMapper: SourceDefinitionMapper = SourceDefinitionMapper(),
        rssRuntimeFactory: ((SourceDefinition) -> any SourceRuntime)? = nil,
        videoRuntimeFactory: ((Source) throws -> any SourceRuntime)? = nil,
        pluginRuntimeFactory: ((SourceDefinition) -> any SourceRuntime)? = nil,
        comicRuntimeFactory: @escaping (Source) -> any SourceRuntime
    ) {
        self.definitionMapper = definitionMapper
        self.comicRuntimeFactory = comicRuntimeFactory
        self.rssRuntimeFactory = rssRuntimeFactory
        self.videoRuntimeFactory = videoRuntimeFactory
        self.pluginRuntimeFactory = pluginRuntimeFactory
    }

    func runtime(for source: Source) throws -> any SourceRuntime {
        return try self.runtime(
            for: self.definitionMapper.definition(from: source),
            source: source
        )
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
            guard let source: Source else {
                throw SourceRuntimeError.invalidInput(
                    "Comic test runtime resolution requires an App Source payload."
                )
            }
            return self.comicRuntimeFactory(source)
        case .rss:
            guard let rssRuntimeFactory: (SourceDefinition) -> any SourceRuntime = self.rssRuntimeFactory else {
                throw SourceRuntimeError.unsupported(
                    .custom("RSS source runtime is not connected in this test resolver.")
                )
            }
            return rssRuntimeFactory(definition)
        case .video:
            guard let source: Source else {
                throw SourceRuntimeError.invalidInput(
                    "Video test runtime resolution requires an App Source payload."
                )
            }
            guard let videoRuntimeFactory: (Source) throws -> any SourceRuntime = self.videoRuntimeFactory else {
                throw SourceRuntimeError.unsupported(
                    .custom("Video source runtime is not connected in this test resolver.")
                )
            }
            return try videoRuntimeFactory(source)
        case .plugin:
            guard let pluginRuntimeFactory: (SourceDefinition) -> any SourceRuntime = self.pluginRuntimeFactory else {
                throw SourceRuntimeError.unsupported(
                    .custom("Plugin source runtime is not connected in this test resolver.")
                )
            }
            return pluginRuntimeFactory(definition)
        }
    }
}
