# BrowseCraft P3-9 Final Re-Freeze Check - Run 1

- 日期：2026-07-04
- 范围：P3-9 Source Config Neutralization / Architecture Hygiene / Runtime Rule Loader Naming 的最终冻结确认。
- 目标：确认进入 P3-10 前，P3-9 架构没有回退、没有未提交代码改动、没有旧过渡命名重新进入源码。

## Git 状态

主 app：

- 仓库：`/Users/xiefei/BrowseCraft`
- 状态：clean
- 最新提交：`9d710ba 收口 Runtime Rule 内部命名`

Core：

- 仓库：`/Users/xiefei/Desktop/BrowseCraftCore`
- 状态：clean
- 最新提交：`cb98fb2 中性化 Runtime 错误文案`

## 当前物理结构

App Application：

```text
BrowseCraft/Application
BrowseCraft/Application/Runtime
BrowseCraft/Application/Runtime/Debug
BrowseCraft/Application/Runtime/Rule
BrowseCraft/Application/UseCases
```

App Runtime/Rule：

```text
BrowseCraft/Application/Runtime/Rule/Loading/RuleSourceChapterLoader.swift
BrowseCraft/Application/Runtime/Rule/Loading/RuleSourceListLoader.swift
BrowseCraft/Application/Runtime/Rule/Loading/RuleSourceReaderLoader.swift
BrowseCraft/Application/Runtime/Rule/Loading/RuleSourceSearchLoader.swift
BrowseCraft/Application/Runtime/Rule/Mapping/RuleSourceItemReferenceMapping.swift
BrowseCraft/Application/Runtime/Rule/Mapping/RuleSourceRuntimeMapping.swift
BrowseCraft/Application/Runtime/Rule/RuleSourceRuntime.swift
```

Core：

```text
BrowseCraftCore/Sources/BrowseCraftCore
BrowseCraftCore/Sources/BrowseCraftCore/Diagnostics
BrowseCraftCore/Sources/BrowseCraftCore/Models
BrowseCraftCore/Sources/BrowseCraftCore/Rule
BrowseCraftCore/Sources/BrowseCraftCore/Rule/Candidate
BrowseCraftCore/Sources/BrowseCraftCore/Runtime
BrowseCraftCore/Sources/BrowseCraftCore/Serialization
BrowseCraftCore/Sources/BrowseCraftCore/Source
```

Core Runtime：

```text
SourceItemReference.swift
SourceRuntime.swift
SourceRuntimeError.swift
SourceRuntimeModels.swift
```

## 架构确认

- `Source` 主字段仍为 `configuration: SourceConfiguration`。
- `source.rule` 仍存在，但作为迁移期 rule-backed source 兼容入口。
- `SourceConfiguration` 支持 `.rule / .rss / .plugin`。
- `SourceRecord` 通过 `sourceConfiguration()` 读取 runtime-neutral config。
- `SourceDefinitionMapper` 将 App `SourceConfiguration` 映射为 Core `SourceDefinition`。
- `SourceRuntimeResolver` 按 `SourceDefinition.kind` 分发 `.rule / .rss / .plugin` runtime。
- `.rss / .plugin` 当前仍是 reserved/not connected，没有被塞回 `SiteRule`。
- `RuleSourceRuntime` 内部使用 `RuleSourceListLoader`、`RuleSourceSearchLoader`、`RuleSourceChapterLoader`、`RuleSourceReaderLoader`。
- App 层 `RefreshSourceUseCase` / `LoadChaptersUseCase` / `LoadReaderChapterUseCase` 仍作为 facade 保留，真实 rule-only 实现在 Runtime/Rule 内部。
- Core 保持纯 Swift 合同与模型层，不依赖 App、RulesKit、GRDB、Nuke 或 UI。

## 静态检查

源码与测试中无以下旧回退命名：

```text
Bridge
Adapter
unsupportedPersistedSourceKind
RuleSourceRefreshUseCase
SearchSourceUseCase
RuleSourceReaderUseCases
SourceDefinitionBridge
SourceRulePrimitiveBridge
SourceRuntimeInputBridge
SourceRuntimeOutputBridge
```

`BrowseCraft/Application/Runtime` 与 Core 中无 `UseCase` / `UseCases` 命名残留。

Core App-only 依赖扫描结果：

- 无 `SwiftUI`
- 无 `UIKit`
- 无 `AppKit`
- 无 `GRDB`
- 无 `Alamofire`
- 无 `Nuke`
- 无 `BrowseCraftRulesKit`

备注：Core `SiteRule.swift` 注释中出现 `SwiftSoup`，只是描述选择器解析链路，不是 import 或依赖。

`git diff --check`：

- 主 app：通过
- Core：通过

## Post-Freeze 命名卫生补充

根据后续架构可读性要求，已补做 App 侧 Core rule typealias 文件改名：

- `BrowseCraft/Domain/Models/SiteRule.swift` -> `BrowseCraft/Domain/Models/CoreRuleTypealiases.swift`
- `BrowseCraft/Domain/Models/ResolvedSiteRule.swift` -> `BrowseCraft/Domain/Models/CoreResolvedRuleTypealiases.swift`
- `BrowseCraft/Domain/Models/RuleCandidateModels.swift` -> `BrowseCraft/Domain/Models/CoreRuleCandidateCompatibility.swift`
- 删除空壳 `BrowseCraft/Domain/Models/ContentType.swift`；`ContentType` 已由 `CoreRuleTypealiases.swift` 暴露。
- `BrowseCraft/Domain/Services/RuleCandidateDraftApplier.swift` -> `BrowseCraft/Domain/Services/CoreRuleCandidateDraftApplierCompatibility.swift`
- 追加物理层归位：上述 4 个 App 侧 Core 兼容入口已集中到 `BrowseCraft/Domain/CoreCompatibility/`。
- `BrowseCraft/Domain/Services/WebViewContentLoader.swift` -> `BrowseCraft/Domain/Services/RenderedPageContentLoader.swift`
- Runtime/Rule 物理层补充归位：
  - loading internals 迁入 `BrowseCraft/Application/Runtime/Rule/Loading/`。
  - mapping internals 迁入 `BrowseCraft/Application/Runtime/Rule/Mapping/`。
  - `RuleSourceReaderLoaders.swift` 拆分为 `RuleSourceChapterLoader.swift` 和 `RuleSourceReaderLoader.swift`。

该补充不改变业务逻辑，只消除 Xcode 物理结构中的误导性文件名。摘要见：

- `TestResults/BrowseCraft-P3-9-Core-Rule-Typealias-Rename-Run1.md`
- `TestResults/BrowseCraft-P3-9-Core-Candidate-Applier-Compatibility-Run1.md`
- `TestResults/BrowseCraft-P3-9-Core-Compatibility-Placement-Run1.md`
- `TestResults/BrowseCraft-P3-9-Rendered-Page-Content-Loader-Naming-Run1.md`
- `TestResults/BrowseCraft-P3-9-Rule-Runtime-Physical-Layer-Run1.md`

补充验证：

- `./scripts/regenerate-project.sh` 通过。
- App targeted tests 45 passed，0 failures。
- App candidate compatibility targeted tests 22 passed，0 failures。
- App CoreCompatibility placement targeted tests 41 passed，0 failures。
- App rendered page loader naming targeted tests 30 passed，0 failures。
- App rule runtime physical layer targeted tests 33 passed，0 failures。

## 测试状态

Freeze check 初始节点没有重新运行测试，引用最近一次已通过结果：

- P3-9.8 App targeted tests：`SourceRuntimeMappingTests` + `RequestConfigUseCaseTests`，28 tests passed，0 failures。
- Core `swift test`：38 tests passed，0 failures。

Post-freeze 命名卫生补充后，又重新运行 App targeted tests：

- `SourceRuntimeMappingTests` + `RequestConfigUseCaseTests` + `RuleDebugSourceMappingTests` + `RuleCandidateDraftApplierTests` + `SwiftSoupRuleCandidateAnalyzerTests`，45 tests passed，0 failures。

## 结论

P3-9 可以重新冻结。

当前架构符合 P3-9 / P3-9.8 计划：

- Source config-neutral 主轴成立。
- Runtime-first 主轴成立。
- Rule-only 实现已归入 Runtime/Rule。
- Core 物理层与依赖边界清晰。
- 旧过渡命名没有回退。

## 下一步

- 下一节：进入 P3-10 计划细化。
- 推荐方向：`P3-10 PluginSourceRuntime MVP`。
- 计划是否需要更新：需要，为 P3-10 新建或细化计划；P3-9 不再追加小节，除非后续发现严重架构回退。
