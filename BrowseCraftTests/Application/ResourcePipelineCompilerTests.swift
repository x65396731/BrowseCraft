import Testing
import BrowseCraftCore
@testable import BrowseCraft
import BrowseCraftRuntime

struct ResourcePipelineCompilerTests {
    @Test func cacheStoresOneCompiledPlanForEquivalentRule() async throws {
        let rule: ResourcePipelineRule = ResourcePipelineRule(
            bindings: [
                "payload": ResourceBindingRule(source: .constant, value: "value")
            ],
            steps: [],
            output: ResourcePipelineOutputRule(
                value: ResourceValueReferenceRule(source: .binding, name: "payload"),
                contentType: .binary
            )
        )
        let cache: ResourcePipelinePlanCache = ResourcePipelinePlanCache()
        let compiler: ResourcePipelineCompiler = ResourcePipelineCompiler()

        _ = try await cache.plan(for: rule, compiler: compiler)
        _ = try await cache.plan(for: rule, compiler: compiler)

        let cachedPlanCount: Int = await cache.cachedPlanCount
        #expect(cachedPlanCount == 1)
    }

    @Test func compilerRejectsFutureStepReferenceBeforeExecution() {
        let rule: ResourcePipelineRule = ResourcePipelineRule(
            bindings: [:],
            steps: [
                ResourcePipelineStepRule(
                    id: "first",
                    operation: .decode(
                        ResourceDecodeOperationRule(
                            input: ResourceValueReferenceRule(source: .step, name: "future"),
                            encoding: .base64
                        )
                    )
                )
            ],
            output: ResourcePipelineOutputRule(
                value: ResourceValueReferenceRule(source: .step, name: "first"),
                contentType: .binary
            )
        )

        #expect(throws: ResourcePipelineExecutorError.missingReference(source: .step, name: "future")) {
            _ = try ResourcePipelineCompiler().compile(rule)
        }
    }
}
