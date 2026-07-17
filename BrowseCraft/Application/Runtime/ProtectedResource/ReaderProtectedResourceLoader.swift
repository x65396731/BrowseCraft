import Foundation

// 中文注释：ReaderProtectedResourceLoader 是 Reader 唯一的受保护图片执行边界，集中处理 V2 与 legacy 双轨策略。

struct ReaderProtectedResourceLoader {
    typealias LegacyLoad = (ProtectedResourceLoadInput) async throws -> ProtectedResourceOutput
    typealias PipelineExecute = (ResourcePipelineExecutionInput) async throws -> ResourcePipelineExecutionOutput

    private let loadLegacy: LegacyLoad
    private let executePipeline: PipelineExecute

    init(
        legacyLoader: ProtectedResourceLoader,
        pipelineExecutor: ResourcePipelineExecutor
    ) {
        self.init(
            loadLegacy: { input in
                try await legacyLoader.load(input)
            },
            executePipeline: { input in
                try await pipelineExecutor.execute(input)
            }
        )
    }

    init(
        loadLegacy: @escaping LegacyLoad,
        executePipeline: @escaping PipelineExecute
    ) {
        self.loadLegacy = loadLegacy
        self.executePipeline = executePipeline
    }

    func load(
        _ reference: ProtectedReaderImageReference,
        context: SourceRequestContext
    ) async throws -> Data {
        switch reference.execution {
        case .legacy(let legacyReference):
            return try await self.loadLegacyReference(legacyReference, context: context)
        case .pipeline(let pipelineReference):
            return try await self.loadPipelineReference(pipelineReference, context: context)
        }
    }

    private func loadPipelineReference(
        _ reference: ResourcePipelineReaderImageReference,
        context: SourceRequestContext
    ) async throws -> Data {
        do {
            let output: ResourcePipelineExecutionOutput = try await self.executePipeline(
                ResourcePipelineExecutionInput(
                    rule: reference.rule,
                    sourceID: reference.sourceID,
                    item: reference.item.mapValues(\.resourcePipelineInputValue),
                    root: reference.root.mapValues(\.resourcePipelineInputValue),
                    context: reference.context.mapValues(\.resourcePipelineInputValue),
                    requestContext: context
                )
            )
            return output.data
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard let legacyFallback: LegacyProtectedReaderImageReference = reference.legacyFallback else {
                throw RuleExecutionError.protectedResource(
                    stage: .image,
                    sourceID: reference.sourceID,
                    reason: "Resource pipeline failed: \(error.localizedDescription)"
                )
            }

            RuleExecutionLogger.log(
                stage: .image,
                event: "resource-pipeline-legacy-fallback",
                fields: [
                    "source": reference.sourceID,
                    "pipelineError": error.localizedDescription
                ]
            )
            return try await self.loadLegacyReference(legacyFallback, context: context)
        }
    }

    private func loadLegacyReference(
        _ reference: LegacyProtectedReaderImageReference,
        context: SourceRequestContext
    ) async throws -> Data {
        let output: ProtectedResourceOutput = try await self.loadLegacy(
            ProtectedResourceLoadInput(
                rule: reference.rule,
                sourceID: reference.sourceID,
                parameters: reference.parameters,
                context: context
            )
        )
        return output.data
    }
}

private extension ReaderResourcePipelineValue {
    var resourcePipelineInputValue: ResourcePipelineInputValue {
        switch self {
        case .string(let value):
            return .string(value)
        case .number(let value):
            return .number(value)
        case .boolean(let value):
            return .boolean(value)
        case .object(let value):
            return .object(value.mapValues(\.resourcePipelineInputValue))
        case .array(let value):
            return .array(value.map(\.resourcePipelineInputValue))
        case .null:
            return .null
        }
    }
}
