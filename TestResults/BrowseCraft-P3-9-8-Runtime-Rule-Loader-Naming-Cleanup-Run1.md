# BrowseCraft P3-9.8 Runtime/Rule Loader Naming Cleanup - Run 1

- 日期：2026-07-04
- 范围：Runtime/Rule 内部命名边界修正。
- 目标：让 `Application/Runtime/Rule/` 内部实现使用 `Loader` 命名，App 层 facade 保留 `UseCase` 命名。

## 改动摘要

- `RuleSourceRefreshUseCase.swift` 改为 `RuleSourceListLoader.swift`。
- `SearchSourceUseCase.swift` 改为 `RuleSourceSearchLoader.swift`。
- `RuleSourceReaderUseCases.swift` 改为 `RuleSourceReaderLoaders.swift`。
- `RuleSourceRuntime` / `SourceRuntimeFactory` 装配参数改为 `listLoader/searchLoader/chapterLoader/readerLoader`。
- App facade 仍保留：
  - `RefreshSourceUseCase`
  - `LoadChaptersUseCase`
  - `LoadReaderChapterUseCase`

## XcodeGen / Pod

- 已运行：`./scripts/regenerate-project.sh`
- 结果：XcodeGen 成功，`pod install` 成功。
- `BrowseCraft.xcodeproj/project.pbxproj` 未作为源码变更提交。
- `Podfile.lock` / `Pods` 未产生待提交变化。

## 测试

命令：

```sh
xcodebuild test -workspace BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -resultBundlePath TestResults/P3-9-8-Run1.xcresult -only-testing:BrowseCraftTests/SourceRuntimeMappingTests -only-testing:BrowseCraftTests/RequestConfigUseCaseTests
```

结果：

- 通过：28 tests / 2 suites。
- 失败：0。
- `.xcresult`：`TestResults/P3-9-8-Run1.xcresult`。

## 当前物理结构

```text
BrowseCraft/Application
BrowseCraft/Application/Runtime
BrowseCraft/Application/Runtime/Debug
BrowseCraft/Application/Runtime/Rule
BrowseCraft/Application/UseCases
```

Runtime/Rule 文件：

```text
BrowseCraft/Application/Runtime/Rule/RuleSourceItemReferenceMapping.swift
BrowseCraft/Application/Runtime/Rule/RuleSourceListLoader.swift
BrowseCraft/Application/Runtime/Rule/RuleSourceReaderLoaders.swift
BrowseCraft/Application/Runtime/Rule/RuleSourceRuntime.swift
BrowseCraft/Application/Runtime/Rule/RuleSourceRuntimeMapping.swift
BrowseCraft/Application/Runtime/Rule/RuleSourceSearchLoader.swift
```

## 偏航检查

- `BrowseCraft/Application/Runtime` 内无 `UseCase` / `UseCases` 命名残留。
- 未恢复 `Bridge` / `Adapter` 命名。
- 未恢复 `unsupportedPersistedSourceKind`。
- Core repo 未改动。
- `git diff --check` 通过。

## 下一步

- 下一节建议：`P3-9 final re-freeze check`。
- 是否需要更新计划：暂不需要新增功能计划；如果后续还发现 App facade 调用点职责混淆，再补 `P3-9.9 App facade call-site cleanup`。
