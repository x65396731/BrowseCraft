# BrowseCraft P3-9.4 Reader Rule Dependency Narrowing

日期：2026-07-04

## 范围

- `ReaderViewModel` 不再直接读取 `source.rule`。
- `ChapterListViewModel` 不再直接读取 `source.rule`。
- 新增 `ResolveReaderSourcePresentationUseCase`，集中处理 Reader / Chapter 展示层需要的 request config：
  - reader image request config
  - detail cover request config
- `AppContainer` 装配 `ResolveReaderSourcePresentationUseCase`。
- 新增 RSS source 的 Reader presentation 测试，确认非 rule source 不会触发 `source.rule` 兼容入口。

## 验证

命令：

```sh
xcodebuild test -workspace BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -resultBundlePath TestResults/P3-9-4-Run1.xcresult -only-testing:BrowseCraftTests/RequestConfigUseCaseTests -only-testing:BrowseCraftTests/SourceRuntimeMappingTests
```

结果：

- 28 tests in 2 suites passed。
- `.xcresult`：`/Users/xiefei/BrowseCraft/TestResults/P3-9-4-Run1.xcresult`

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

- `BrowseCraft/Features/Reader` 已无直接 `source.rule` / `RuleResolver`。
- `BrowseCraft/Features/Library` 也保持无直接 `source.rule` / `RuleResolver`。
- `ResolveReaderSourcePresentationUseCase` 内仍有 rule-specific 分流，这是刻意保留在应用层的迁移边界；非 rule source 返回 nil request config。
- `LoadChaptersUseCase` / `LoadReaderChapterUseCase` 内仍有 rule-only 执行逻辑，留到 P3-9.5 判断是否需要重新放置或标注边界。
- 物理目录仍存在 `BrowseCraft/Application/Adapters` 空壳残留，本节未处理。
- 本节未新增/移动 Swift 文件，未运行 XcodeGen。

## 下一节

P3-9.5：Rule-only use case placement。

目标：重新判断 `SearchSourceUseCase` / `LoadReaderChapterUseCase` / `LoadChaptersUseCase` 这些 rule-only 执行用例是否仍应作为 App 共享 use case，还是应明确收进 `RuleSourceRuntime` 边界或改名标注 rule-only。是否需要更新计划：暂不需要，P3-9.5 正是处理本节留下的边界判断。
