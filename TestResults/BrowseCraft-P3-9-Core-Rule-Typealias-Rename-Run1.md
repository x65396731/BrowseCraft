# BrowseCraft P3-9 Core Rule Typealias Rename - Run 1

- 日期：2026-07-04
- 范围：App 侧 Core rule typealias / compatibility 文件命名卫生。
- 目标：避免 Xcode 物理结构里继续显示 `SiteRule.swift` / `ResolvedSiteRule.swift` / `RuleCandidateModels.swift` 这类容易误判为 App-owned 模型的文件名，让 App 侧文件名明确表达它们只是 Core 兼容入口。

## 改动

- `BrowseCraft/Domain/Models/SiteRule.swift` 改名为 `BrowseCraft/Domain/Models/CoreRuleTypealiases.swift`。
- `BrowseCraft/Domain/Models/ResolvedSiteRule.swift` 改名为 `BrowseCraft/Domain/Models/CoreResolvedRuleTypealiases.swift`。
- `BrowseCraft/Domain/Models/RuleCandidateModels.swift` 改名为 `BrowseCraft/Domain/Models/CoreRuleCandidateCompatibility.swift`。
- 删除空壳 `BrowseCraft/Domain/Models/ContentType.swift`；`ContentType` 已由 `CoreRuleTypealiases.swift` 暴露。
- 更新文件头注释，说明真实规则模型、resolved graph、candidate 合同定义在 `BrowseCraftCore`。

## 追加命名卫生

- `BrowseCraft/Domain/Services/RuleCandidateDraftApplier.swift` 改名为 `BrowseCraft/Domain/Services/CoreRuleCandidateDraftApplierCompatibility.swift`。
- 该文件只是 `BrowseCraftCore.SourceRuleCandidateDraftApplier` 的 App 侧兼容入口，不改变调用点和业务行为。
- 追加摘要：`TestResults/BrowseCraft-P3-9-Core-Candidate-Applier-Compatibility-Run1.md`。

## 不变项

- 不改变 `BrowseCraftCore.SiteRule` 真实模型位置。
- 不改变 `Source.configuration` 主轴。
- 不改变 `RuleSourceRuntime` 行为。
- 不改变 App facade / Runtime Loader 关系。
- 不改业务逻辑和 UI。

## XcodeGen / Pod

- 已运行：`./scripts/regenerate-project.sh`
- 结果：XcodeGen 成功，`pod install` 成功。
- 生成物未产生待提交状态。

## 测试

命令：

```sh
xcodebuild test -workspace BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -resultBundlePath TestResults/P3-9-10-Core-Typealias-Physical-Hygiene-Run3.xcresult -only-testing:BrowseCraftTests/SourceRuntimeMappingTests -only-testing:BrowseCraftTests/RequestConfigUseCaseTests -only-testing:BrowseCraftTests/RuleDebugSourceMappingTests -only-testing:BrowseCraftTests/RuleCandidateDraftApplierTests -only-testing:BrowseCraftTests/SwiftSoupRuleCandidateAnalyzerTests
```

结果：

- 通过：45 tests / 5 suites。
- 失败：0。
- `.xcresult`：`TestResults/P3-9-10-Core-Typealias-Physical-Hygiene-Run3.xcresult`。

## 当前 Domain/Models 结构

```text
BuiltInSource.swift
ChapterLink.swift
ContentItem.swift
CoreResolvedRuleTypealiases.swift
CoreRuleCandidateCompatibility.swift
CoreRuleTypealiases.swift
ReaderChapter.swift
ReadingHistory.swift
RuleDebugModels.swift
Source.swift
SourceConfiguration.swift
SourceType.swift
```

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
- `BrowseCraft/Domain/Models/SiteRule.swift` 和 `BrowseCraft/Domain/Models/ResolvedSiteRule.swift` 已不存在。
- `BrowseCraft/Domain/Models/RuleCandidateModels.swift` 已不存在。
- `BrowseCraft/Domain/Models/ContentType.swift` 已不存在。
- `BrowseCraft/Domain/Services/RuleCandidateDraftApplier.swift` 已不存在。
- Core repo 未改动。
- `git diff --check` 通过。

## 下一步

- P3-9 仍可冻结。
- 下一节：进入 P3-10 计划细化。
- 计划是否需要更新：P3-9 不需要新增功能计划；P3-10 需要新建或细化计划。
