# BrowseCraft P3-9.1 Source Model Neutralization

日期：2026-07-04

## 范围

- 将 `Source` 的主存储字段从 `rule: SiteRule` 调整为 `configuration: SourceConfiguration`。
- 保留 `Source(rule:)` 初始化器和可读写 `source.rule` 兼容入口，避免一次性牵动 UI、Reader、Library 和现有规则测试。
- `SourceRecord.init(source:)` 不再无条件从 `source.rule` 编码；非 rule 配置写入 `configJSON`，legacy `ruleJSON` 只为兼容保留 `{}`。
- `SourceRecord.domainModel()` 对 rule 配置直接回填 `configuration`，避免丢失 `RuleSourceConfiguration` 的 metadata/isEditable。
- `SourceDefinitionMapper` 不再为了构建 definition 强读 `source.rule`，改从 `source.ruleConfiguration` 获取 rule version。

## 验证

命令：

```sh
env -u GEM_HOME -u GEM_PATH pod install
xcodebuild test -workspace BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -resultBundlePath TestResults/P3-9-1-Run4.xcresult -only-testing:BrowseCraftTests/SourceRuntimeMappingTests -only-testing:BrowseCraftTests/RequestConfigUseCaseTests -only-testing:BrowseCraftTests/RuleManagementUseCaseTests -only-testing:BrowseCraftTests/RulePackageUseCaseTests
```

结果：

- 35 tests in 4 suites passed。
- `.xcresult`：`/Users/xiefei/BrowseCraft/TestResults/P3-9-1-Run4.xcresult`

## 过程备注

- `Run1` 失败：沙箱无法写 DerivedData / 连接 CoreSimulatorService。
- `Run2` 失败：未使用 workspace，Pods 依赖未接入，出现 `Alamofire/GRDB/Nuke/SwiftSoup` 无法解析。
- 已执行 `pod install`，随后改用 `BrowseCraft.xcworkspace`。
- `Run3` 失败：临时 `Source.kind` 暴露 `SourceDefinitionKind`，导致 `Source.swift` 需要 Core 类型；已删除该无调用点便捷属性。
- `Run4` 通过。

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

- `rg "Bridge|Adapter" BrowseCraft BrowseCraftTests` 无命名命中。
- 物理目录仍存在 `BrowseCraft/Application/Adapters`，本次未动；不阻塞 P3-9.1，但应在后续结构卫生中处理。
- P3-9.1 后 `Source` 已以 `SourceConfiguration` 为主轴，但 `source.rule` 兼容入口仍存在，后续 P3-9.3/P3-9.4 继续收窄 UI/Reader/Library 的 rule-specific 读取。

## 下一节

P3-9.2：SourceRecord / repository neutralization。

目标：让 `.rss` / `.plugin` 配置也可以稳定还原为 runtime-neutral `Source`，不再在 `SourceRecord.domainModel()` 阶段抛 unsupported。是否需要更新计划：不需要，P3-9.2 仍符合当前 Source Config Neutralization 主线。
