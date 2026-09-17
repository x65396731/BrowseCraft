import Foundation
import BrowseCraftCore
@testable import BrowseCraft
import BrowseCraftDomain
import BrowseCraftRuntime

// 中文注释：测试专用闭包 resolver，避免生产 Runtime 为测试注入保留第二套分发实现。
// resolver 是 Sendable（跨 Task 共享），因此工厂闭包必须是 @Sendable；SourceRuntime 本身已要求 Sendable。
struct TestSourceRuntimeResolver: SourceRuntimeResolving {
    private let definitionMapper: SourceDefinitionMapper
    private let comicRuntimeFactory: @Sendable (Source) -> any SourceRuntime
    private let videoRuntimeFactory: (@Sendable (Source) throws -> any SourceRuntime)?
    private let pluginRuntimeFactory: (@Sendable (SourceDefinition) -> any SourceRuntime)?
    private let bookRuntimeFactory: (@Sendable (Source) -> any SourceRuntime)?

    init(
        definitionMapper: SourceDefinitionMapper = SourceDefinitionMapper(),
        videoRuntimeFactory: (@Sendable (Source) throws -> any SourceRuntime)? = nil,
        pluginRuntimeFactory: (@Sendable (SourceDefinition) -> any SourceRuntime)? = nil,
        bookRuntimeFactory: (@Sendable (Source) -> any SourceRuntime)? = nil,
        comicRuntimeFactory: @escaping @Sendable (Source) -> any SourceRuntime
    ) {
        self.definitionMapper = definitionMapper
        self.comicRuntimeFactory = comicRuntimeFactory
        self.videoRuntimeFactory = videoRuntimeFactory
        self.pluginRuntimeFactory = pluginRuntimeFactory
        self.bookRuntimeFactory = bookRuntimeFactory
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
        case .video:
            guard let source: Source else {
                throw SourceRuntimeError.invalidInput(
                    "Video test runtime resolution requires an App Source payload."
                )
            }
            guard let videoRuntimeFactory: @Sendable (Source) throws -> any SourceRuntime = self.videoRuntimeFactory else {
                throw SourceRuntimeError.unsupported(
                    .custom("Video source runtime is not connected in this test resolver.")
                )
            }
            return try videoRuntimeFactory(source)
        case .book:
            guard let source: Source,
                  let bookRuntimeFactory: @Sendable (Source) -> any SourceRuntime = self.bookRuntimeFactory else {
                throw SourceRuntimeError.unsupported(
                    .custom("Book source runtime is not connected in this test resolver.")
                )
            }
            return bookRuntimeFactory(source)
        case .plugin:
            guard let pluginRuntimeFactory: @Sendable (SourceDefinition) -> any SourceRuntime = self.pluginRuntimeFactory else {
                throw SourceRuntimeError.unsupported(
                    .custom("Plugin source runtime is not connected in this test resolver.")
                )
            }
            return pluginRuntimeFactory(definition)
        }
    }
}
