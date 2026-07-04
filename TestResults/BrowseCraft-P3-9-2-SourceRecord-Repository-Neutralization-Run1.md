# BrowseCraft P3-9.2 SourceRecord / Repository Neutralization

日期：2026-07-04

## 范围

- `SourceRecord.domainModel()` 不再对 `.rss` / `.plugin` 配置抛 `unsupportedPersistedSourceKind`。
- `SourceRecord` 现在会把已解码的 `SourceConfiguration` 直接还原到 `Source(configuration:)`，让持久化层保持 runtime-neutral。
- 删除旧的 `SourceRecordDecodingError.unsupportedPersistedSourceKind` case。
- 新增 repository 往返测试，确认 RSS source 保存后仍以 `.rss` configuration 读回，且 legacy `ruleJSON` 只保留 `{}` 兼容位。
- 更新 RSS record 解码测试，从“期望抛错”改为“期望还原 runtime-neutral Source”。

## 验证

命令：

```sh
xcodebuild test -workspace BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -resultBundlePath TestResults/P3-9-2-Run1.xcresult -only-testing:BrowseCraftTests/RequestConfigUseCaseTests -only-testing:BrowseCraftTests/SourceRuntimeMappingTests
```

结果：

- 26 tests in 2 suites passed。
- `.xcresult`：`/Users/xiefei/BrowseCraft/TestResults/P3-9-2-Run1.xcresult`

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

- `rg "unsupportedPersistedSourceKind|Bridge|Adapter" BrowseCraft BrowseCraftTests` 无命中。
- `Application/Adapters` 目录仍是物理空壳残留，本节未处理。
- storage/repository 已能保存并读取非 rule source config；runtime resolver 仍按计划拒绝未接入的 RSS/Plugin runtime，本节没有提前实现 RSS 功能。

## 下一节

P3-9.3：Library rule dependency narrowing。

目标：收窄 `LibraryViewModel` / Library 列表入口对 `source.rule` 的直接读取，优先通过 runtime definition/context 获取通用入口信息；保留 rule-only 细节在 `RuleSourceRuntime` 内部。是否需要更新计划：暂不需要，P3-9.3 仍符合当前 Source Config Neutralization 主线。
