# BrowseCraft P3-9 Core Candidate Applier Compatibility - Run 1

- 日期：2026-07-05
- 范围：App 侧 Core rule candidate draft applier 兼容入口命名卫生。
- 目标：避免 `Domain/Services` 中继续显示 `RuleCandidateDraftApplier.swift`，让文件名明确表达它只是 Core 实现的 App 兼容入口。

## 改动

- `BrowseCraft/Domain/Services/RuleCandidateDraftApplier.swift` 改名为 `BrowseCraft/Domain/Services/CoreRuleCandidateDraftApplierCompatibility.swift`。
- 增加文件头注释，说明真实实现定义在 `BrowseCraftCore`。
- 保留 App 侧 `RuleCandidateDraftApplier` typealias，不改变调用点和业务行为。

## 不变项

- 不改变 `BrowseCraftCore.SourceRuleCandidateDraftApplier`。
- 不改变 `RuleCandidateDraftApplierTests` 的测试语义。
- 不改变 rule candidate draft apply 行为。
- 不改变 `Source.configuration` / runtime-first 主轴。

## XcodeGen / Pod

- 已运行：`./scripts/regenerate-project.sh`
- 结果：XcodeGen 成功，`pod install` 成功。
- 生成物未产生待提交状态。

## 测试

命令：

```sh
xcodebuild test -workspace BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -resultBundlePath TestResults/P3-9-11-Core-Candidate-Applier-Compatibility-Run2.xcresult -only-testing:BrowseCraftTests/RuleCandidateDraftApplierTests -only-testing:BrowseCraftTests/RuleDebugSourceMappingTests -only-testing:BrowseCraftTests/SourceRuntimeMappingTests
```

结果：

- 通过：22 tests / 3 suites。
- 失败：0。
- `.xcresult`：`TestResults/P3-9-11-Core-Candidate-Applier-Compatibility-Run2.xcresult`。

## 当前 Domain/Services 结构

```text
CookieHeaderResolver.swift
CoreRuleCandidateDraftApplierCompatibility.swift
HTTPClient.swift
RuleCandidateAnalyzingService.swift
RuleParsingService.swift
URLResolvingService.swift
WebViewContentLoader.swift
```

## 偏航检查

- 源码和测试中无 `Bridge` / `Adapter` / `unsupportedPersistedSourceKind`。
- 源码和测试中无旧 `RuleSourceRefreshUseCase` / `SearchSourceUseCase` / `RuleSourceReaderUseCases`。
- `BrowseCraft/Domain/Services/RuleCandidateDraftApplier.swift` 已不存在。
- Core repo 未改动。
- `git diff --check` 通过。

## 下一步

- P3-9 仍可冻结。
- 下一节：进入 P3-10 计划细化。
- 计划是否需要更新：P3-9 不需要新增功能计划；P3-10 需要新建或细化计划。
