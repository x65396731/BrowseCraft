import Foundation
import BrowseCraftCore

protocol SourceRuntimeResolving {
    func runtime(for source: Source) throws -> any SourceRuntime
}

struct SourceRuntimeResolver: SourceRuntimeResolving {
    private let definitionMapper: SourceDefinitionMapper
    private let ruleRuntimeFactory: (Source) -> any SourceRuntime
    private let rssRuntimeFactory: ((SourceDefinition) -> any SourceRuntime)?
    private let pluginRuntimeFactory: ((SourceDefinition) -> any SourceRuntime)?

    init(
        definitionMapper: SourceDefinitionMapper = SourceDefinitionMapper(),
        rssRuntimeFactory: ((SourceDefinition) -> any SourceRuntime)? = nil,
        pluginRuntimeFactory: ((SourceDefinition) -> any SourceRuntime)? = nil,
        ruleRuntimeFactory: @escaping (Source) -> any SourceRuntime
    ) {
        self.definitionMapper = definitionMapper
        self.ruleRuntimeFactory = ruleRuntimeFactory
        self.rssRuntimeFactory = rssRuntimeFactory
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
        switch definition.kind {
        case .rule:
            guard let source: Source = source else {
                throw SourceRuntimeError.invalidInput("Rule runtime resolution requires an App Source payload.")
            }
            return self.ruleRuntimeFactory(source)
        case .rss:
            if let rssRuntimeFactory: (SourceDefinition) -> any SourceRuntime = self.rssRuntimeFactory {
                return rssRuntimeFactory(definition)
            }

            throw SourceRuntimeError.unsupported(
                .custom("RSS source runtime is not connected in this resolver.")
            )
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
