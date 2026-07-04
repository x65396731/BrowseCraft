# BrowseCraft P3-9 Core Compatibility Placement - Run 1

- 日期：2026-07-05
- 范围：App 侧 Core compatibility 物理层归位。
- 目标：把 App 侧 Core typealias / compatibility 入口从 `Domain/Models`、`Domain/Services` 收拢到 `Domain/CoreCompatibility`，避免 Models/Services 目录承载不属于自身职责的兼容文件。

## 改动

- `BrowseCraft/Domain/Models/CoreRuleTypealiases.swift` -> `BrowseCraft/Domain/CoreCompatibility/CoreRuleTypealiases.swift`
- `BrowseCraft/Domain/Models/CoreResolvedRuleTypealiases.swift` -> `BrowseCraft/Domain/CoreCompatibility/CoreResolvedRuleTypealiases.swift`
- `BrowseCraft/Domain/Models/CoreRuleCandidateCompatibility.swift` -> `BrowseCraft/Domain/CoreCompatibility/CoreRuleCandidateCompatibility.swift`
- `BrowseCraft/Domain/Services/CoreRuleCandidateDraftApplierCompatibility.swift` -> `BrowseCraft/Domain/CoreCompatibility/CoreRuleCandidateDraftApplierCompatibility.swift`
- 更新文件头注释，说明 `Domain/CoreCompatibility` 是 App 侧 Core 兼容入口集中区。

## 不变项

- 不改变任何 typealias 名称。
- 不改变调用点和业务行为。
- 不改变 `BrowseCraftCore`。
- 不改变 `Source.configuration` / runtime-first 主轴。

## XcodeGen / Pod

- 已运行：`./scripts/regenerate-project.sh`
- 结果：XcodeGen 成功，`pod install` 成功。
- 生成物未产生待提交状态。

## 测试

命令：

```sh
xcodebuild test -workspace BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -resultBundlePath TestResults/P3-9-12-Core-Compatibility-Placement-Run2.xcresult -only-testing:BrowseCraftTests/RuleCandidateDraftApplierTests -only-testing:BrowseCraftTests/RuleDebugSourceMappingTests -only-testing:BrowseCraftTests/SourceRuntimeMappingTests -only-testing:BrowseCraftTests/RequestConfigUseCaseTests
```

结果：

- 通过：41 tests / 4 suites。
- 失败：0。
- `.xcresult`：`TestResults/P3-9-12-Core-Compatibility-Placement-Run2.xcresult`。

## 当前 Domain 结构

```text
Domain/CoreCompatibility
Domain/Models
Domain/Repositories
Domain/Services
```

## 当前 Domain/CoreCompatibility 结构

```text
CoreResolvedRuleTypealiases.swift
CoreRuleCandidateCompatibility.swift
CoreRuleCandidateDraftApplierCompatibility.swift
CoreRuleTypealiases.swift
```

## 偏航检查

- `Domain/Models` 不再承载 Core typealias 入口。
- `Domain/Services` 不再承载 Core draft applier compatibility 入口。
- 源码和测试中无 `Bridge` / `Adapter` / `unsupportedPersistedSourceKind`。
- 源码和测试中无旧 `RuleSourceRefreshUseCase` / `SearchSourceUseCase` / `RuleSourceReaderUseCases`。
- Core repo 未改动。
- `git diff --check` 通过。

## 下一步

- P3-9 仍可冻结。
- 下一节：进入 P3-10 计划细化。
- 计划是否需要更新：P3-9 不需要新增功能计划；P3-10 需要新建或细化计划。
