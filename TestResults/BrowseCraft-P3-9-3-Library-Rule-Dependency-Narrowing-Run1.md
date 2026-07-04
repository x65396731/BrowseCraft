# BrowseCraft P3-9.3 Library Rule Dependency Narrowing

日期：2026-07-04

## 范围

- `LibraryViewModel` 不再直接读取 `source.rule`。
- 新增 `ResolveLibrarySourcePresentationUseCase`，集中处理 Library 展示所需的 source presentation：
  - list tabs
  - image request config
  - primary action 是否直接打开 reader
  - selected list context
- `AppContainer` 装配 `ResolveLibrarySourcePresentationUseCase`。
- 新增 RSS source 的 Library presentation 测试，确认非 rule source 不会触发 `source.rule` 兼容入口，也不会解析 rule runtime。

## 验证

命令：

```sh
xcodebuild test -workspace BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -resultBundlePath TestResults/P3-9-3-Run2.xcresult -only-testing:BrowseCraftTests/RequestConfigUseCaseTests -only-testing:BrowseCraftTests/SourceRuntimeMappingTests
```

结果：

- 27 tests in 2 suites passed。
- `.xcresult`：`/Users/xiefei/BrowseCraft/TestResults/P3-9-3-Run2.xcresult`

## 过程备注

- `Run1` 失败：新增 RSS fixture 使用了错误的 `ContentItem` 初始化参数。
- 已修正为真实 `ContentItem` 参数：`type`、`latestText`、`updatedAt`、`listOrder`、`listContext`。
- `Run2` 通过。

## 当前结构检查

```text
BrowseCraft/
  App/
  Application/
    Adapters/        # 空壳残留，后续架构卫生项
    Runtime/
      Debug/
      Rule/
    UseCases/
  Domain/
    Models/
    Repositories/
    Services/
  Features/
    History/
    Library/
    Reader/
    Settings/
    Sources/
  Infrastructure/
    Database/
      Records/
      Repositories/
    Network/
    Parsing/
  Shared/
    Errors/
    Logging/
    UI/
```

漂移检查：

- `LibraryViewModel` / `BrowseCraft/Features/Library` 已无直接 `source.rule` 读取。
- `ResolveLibrarySourcePresentationUseCase` 内仍有 rule-specific 分流，这是刻意保留在应用层的迁移边界；非 rule source 返回空 tabs / nil request / 非直接 reader。
- `rg "Bridge|Adapter|unsupportedPersistedSourceKind" BrowseCraft BrowseCraftTests` 无命名命中。
- 物理目录仍存在 `BrowseCraft/Application/Adapters` 空壳残留，本节未处理。
- 本节未新增/移动 Swift 文件，未运行 XcodeGen。

## 下一节

P3-9.4：Reader rule dependency narrowing。

目标：收窄 Reader / Chapter 入口对 `source.rule` 的直接读取，让 Reader 层尽量通过 runtime output / handoff context 工作；rule-specific 解析细节继续保留在 `RuleSourceRuntime` 或 rule-only use case 内。是否需要更新计划：暂不需要，P3-9.4 仍符合 Source Config Neutralization 主线。
