import BrowseCraftCore
import Foundation

/// 经过完整结构检查、可直接交给执行器运行的不可变计划。
struct CompiledResourcePipeline: Sendable {
    let rule: ResourcePipelineRule
}

struct ResourcePipelineCompiler: Sendable {
    func compile(_ rule: ResourcePipelineRule) throws -> CompiledResourcePipeline {
        guard rule.version == 2 else {
            throw ResourcePipelineExecutorError.unsupportedVersion(rule.version)
        }

        for (name, binding): (String, ResourceBindingRule) in rule.bindings {
            guard name.isEmpty == false else {
                throw ResourcePipelineExecutorError.invalidBinding(name: name, reason: "empty name")
            }
            switch binding.source {
            case .constant:
                guard binding.value != nil else {
                    throw ResourcePipelineExecutorError.invalidBinding(name: name, reason: "missing value")
                }
            case .item, .root, .context:
                guard let path: String = binding.path,
                      path.isEmpty == false else {
                    throw ResourcePipelineExecutorError.invalidBinding(name: name, reason: "missing path")
                }
            }
        }

        let bindingNames: Set<String> = Set(rule.bindings.keys)
        var availableSteps: Set<String> = []
        for step: ResourcePipelineStepRule in rule.steps {
            guard step.id.isEmpty == false else {
                throw ResourcePipelineExecutorError.invalidStep(id: step.id, reason: "empty id")
            }
            guard availableSteps.contains(step.id) == false else {
                throw ResourcePipelineExecutorError.duplicateStepID(step.id)
            }
            guard bindingNames.contains(step.id) == false else {
                throw ResourcePipelineExecutorError.ambiguousName(step.id)
            }

            try self.validate(
                step.operation,
                stepID: step.id,
                bindingNames: bindingNames,
                availableSteps: availableSteps
            )
            for reference: ResourceValueReferenceRule in self.references(in: step.operation) {
                try self.validate(
                    reference,
                    bindingNames: bindingNames,
                    availableSteps: availableSteps
                )
            }
            availableSteps.insert(step.id)
        }

        try self.validate(
            rule.output.value,
            bindingNames: bindingNames,
            availableSteps: availableSteps
        )
        return CompiledResourcePipeline(rule: rule)
    }

    private func validate(
        _ operation: ResourcePipelineOperationRule,
        stepID: String,
        bindingNames: Set<String>,
        availableSteps: Set<String>
    ) throws {
        switch operation {
        case .request(let rule):
            guard rule.urlTemplate.isEmpty == false else {
                throw ResourcePipelineExecutorError.invalidStep(id: stepID, reason: "empty URL template")
            }
            for token: String in ResourcePipelineTemplateResolver.tokens(in: rule) {
                if token.hasPrefix("binding.") {
                    let name: String = String(token.dropFirst("binding.".count))
                    guard bindingNames.contains(name) else {
                        throw ResourcePipelineExecutorError.unresolvedTemplateToken(token)
                    }
                    continue
                }
                if token.hasPrefix("step.") {
                    let stepPath: String = String(token.dropFirst("step.".count))
                    let name: String = stepPath.split(separator: ".", maxSplits: 1).first.map(String.init) ?? ""
                    guard availableSteps.contains(name) else {
                        throw ResourcePipelineExecutorError.unresolvedTemplateToken(token)
                    }
                    continue
                }
                throw ResourcePipelineExecutorError.unresolvedTemplateToken(token)
            }
        case .extract(let rule):
            guard rule.path.isEmpty == false else {
                throw ResourcePipelineExecutorError.invalidStep(id: stepID, reason: "empty extract path")
            }
        case .slice(let rule):
            guard rule.offset >= 0,
                  rule.length.map({ $0 >= 0 }) ?? true else {
                throw ResourcePipelineExecutorError.invalidStep(id: stepID, reason: "negative slice")
            }
        case .split(let rule):
            guard rule.delimiter.isEmpty == false,
                  rule.fields.isEmpty == false,
                  Set(rule.fields).count == rule.fields.count,
                  rule.fields.allSatisfy({ $0.isEmpty == false }) else {
                throw ResourcePipelineExecutorError.invalidStep(id: stepID, reason: "invalid split declaration")
            }
        case .decode, .hash, .decrypt:
            break
        }
    }

    private func validate(
        _ reference: ResourceValueReferenceRule,
        bindingNames: Set<String>,
        availableSteps: Set<String>
    ) throws {
        switch reference.source {
        case .binding:
            guard bindingNames.contains(reference.name) else {
                throw ResourcePipelineExecutorError.missingReference(source: .binding, name: reference.name)
            }
        case .step:
            guard availableSteps.contains(reference.name) else {
                throw ResourcePipelineExecutorError.missingReference(source: .step, name: reference.name)
            }
        }
    }

    private func references(
        in operation: ResourcePipelineOperationRule
    ) -> [ResourceValueReferenceRule] {
        switch operation {
        case .request:
            return []
        case .extract(let rule):
            return [rule.input]
        case .decode(let rule):
            return [rule.input]
        case .hash(let rule):
            return [rule.input]
        case .slice(let rule):
            return [rule.input]
        case .split(let rule):
            return [rule.input]
        case .decrypt(let rule):
            return [rule.input, rule.key, rule.iv]
        }
    }
}

actor ResourcePipelinePlanCache {
    private let maximumEntryCount: Int
    private var plans: [ResourcePipelineRule: CompiledResourcePipeline] = [:]
    private var order: [ResourcePipelineRule] = []

    init(maximumEntryCount: Int = 64) {
        self.maximumEntryCount = max(1, maximumEntryCount)
    }

    var cachedPlanCount: Int {
        return self.plans.count
    }

    func plan(
        for rule: ResourcePipelineRule,
        compiler: ResourcePipelineCompiler
    ) throws -> CompiledResourcePipeline {
        if let plan: CompiledResourcePipeline = self.plans[rule] {
            self.touch(rule)
            return plan
        }

        let plan: CompiledResourcePipeline = try compiler.compile(rule)
        self.plans[rule] = plan
        self.touch(rule)
        while self.order.count > self.maximumEntryCount {
            let oldestRule: ResourcePipelineRule = self.order.removeFirst()
            self.plans.removeValue(forKey: oldestRule)
        }
        return plan
    }

    private func touch(_ rule: ResourcePipelineRule) {
        self.order.removeAll { $0 == rule }
        self.order.append(rule)
    }
}
