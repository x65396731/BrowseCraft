# BrowseCraft P3-9.0 Source Config Neutralization 中文详细计划

- 日期：2026-07-04
- 主题：把 P3-9 从 RSS / 视频 / Plugin 功能实现，改为先修正 App 对 `Source.rule: SiteRule` 的强依赖。
- 当前前置状态：
  - P3-8 已把运行时主轴收口为 `SourceDefinition + SourceRuntime`。
  - DB 已有 `kind + configJSON`，旧 `type + ruleJSON` 仍兼容。
  - `SourceRecord.sourceConfiguration()` 已能直接读取 `.rule / .rss / .plugin` config。
  - 但 App-domain `Source` 仍强持有 `rule: SiteRule`，这会继续卡住 RSS、视频、Plugin 等后续 runtime。

## 一句话目标

P3-9 的目标不是做新功能，而是把 App 内部的 source 主模型从“所有 source 都是 SiteRule”改成“所有 source 都有 SourceConfiguration；rule 只是其中一种配置”。

目标形态：

```swift
struct Source {
    var id: String
    var name: String
    var baseURL: String
    var configuration: SourceConfiguration
    var enabled: Bool
    var createdAt: Date
    var updatedAt: Date
}
```

兼容形态：

```swift
extension Source {
    var kind: SourceDefinitionKind { configuration.kind }
    var ruleConfiguration: RuleSourceConfiguration? { ... }
    var ruleIfAvailable: SiteRule? { ... }
}
```

也就是说，规则源仍然能工作，规则编辑器仍然能读写 SiteRule，但 `SiteRule` 不再是所有 source 的必备字段。

## 为什么现在必须做

之前我们讨论 RSS、视频、Plugin 时反复撞到同一个问题：只要 `Source` 还强持有 `rule: SiteRule`，任何非规则 source 都必须被伪装成 rule source，或者在读取时直接 unsupported。

这会造成三个问题：

- 架构问题：runtime-first 只是 resolver 层成立，domain model 仍是 rule-first。
- 产品问题：后续视频解析如果继续塞进 SiteRule，PluginSourceRuntime 会被继续推迟。
- 工程问题：Library / Reader / Search / ReaderChapter 里会继续默认 `source.rule` 一定存在，第二 runtime 一接入就会到处补空值和分支。

所以 P3-9 先不做 RSS、不做视频、不做 Plugin，而是拆这个真正的强依赖。

## P3-9.1 Source 模型中性化

目标：把 `Source` 的主字段从 `rule: SiteRule` 改为 `configuration: SourceConfiguration`。

预计改动：

- 修改 `BrowseCraft/Domain/Models/Source.swift`。
- `Source` 增加或改为持有 `configuration: SourceConfiguration`。
- 当前所有构造 `Source(rule:)` 的地方改成构造 `.rule(RuleSourceConfiguration(...))`。
- 保留兼容访问器，例如：
  - `ruleConfiguration`
  - `ruleIfAvailable`
  - 如确实需要，也可以暂留 `rule` computed property，但必须是兼容层，不再是存储字段。
- `Source.isBuiltIn` 仍按 id 判断，暂不扩大范围。

不做：

- 不改规则编辑 UI 的交互。
- 不改 Reader 行为。
- 不引入 RSS / Plugin 运行逻辑。
- 不删除 `SiteRule`。

验收：

- App 中大部分代码仍能通过兼容访问器读取 rule-backed source。
- 新的 `Source` 可以表达 `.rss` / `.plugin` configuration，即使 UI 还不展示它。
- `Source` 本体不再要求每个 source 都有 `SiteRule`。

建议测试：

- `SourceRuntimeMappingTests`
- `RequestConfigUseCaseTests`
- 必要时补一个 `SourceConfiguration` / `Source` model test。

主要风险：

- `Source` 构造点很多，容易漏改。
- 如果一次性把所有 `source.rule` 调用都改掉，范围会变大。所以 P3-9.1 只改模型和兼容入口，不强行清空所有调用。

## P3-9.2 SourceRecord / Repository 中性化

目标：让 DB repository 可以返回 runtime-neutral `Source`，而不是 `.rss/.plugin` 一律 unsupported。

预计改动：

- 修改 `BrowseCraft/Infrastructure/Database/Records/SourceRecord.swift`。
- 修改 `GRDBSourceRepository` 相关测试。
- `SourceRecord.domainModel()` 使用 `sourceConfiguration()` 构造 `Source(configuration:)`。
- 旧 `ruleJSON` rows 继续能读取为 `.rule(...)`。
- 新 `kind=rss/configJSON` rows 能读取为 `Source(configuration: .rss(...))`。
- 新 `kind=plugin/configJSON` rows 能读取为 `Source(configuration: .plugin(...))`，但不执行插件。

不做：

- 不显示 RSS / Plugin source。
- 不执行 RSS / Plugin runtime。
- 不改变 DB 旧字段的兼容策略。

验收：

- rule source 读写不回退。
- RSS / Plugin source record 可以变成 domain `Source`。
- 非 rule source 不再需要伪造 `SiteRule`。

建议测试：

- repository 写入 rule config 后读回。
- legacy `ruleJSON` row 读回。
- fixture RSS config row 读回。
- fixture Plugin config row 读回。

主要风险：

- 现有 `fetchSources()` 被 UI 调用，如果返回非 rule source，而 UI 仍默认读 rule，可能触发 UI 层问题。因此 P3-9.2 可以先通过测试构造验证，实际 UI 展示策略在 P3-9.3 收窄。

## P3-9.3 Library 规则依赖收窄

目标：Library 不再默认每个 source 都能 `source.rule.availableListTabs`。

当前问题：

- `LibraryViewModel` 仍根据 `source.rule` 推导 tabs。
- image request config、direct-reader 等行为仍可能直接读取 rule。
- 这对 rule source 合理，但对 RSS / Plugin / 未来 media source 不合理。

预计改动：

- 给 `LibraryViewModel` 增加明确的 rule source 判断。
- rule-backed source 才读取 rule tabs。
- 非 rule source 暂时显示空 tab / 默认 tab / unsupported 状态，而不是崩溃或伪装 rule。
- 如果已有 runtime-facing list refresh 路径可用，优先走 runtime resolver，不新增共享 rule 逻辑。

不做：

- 不实现 RSS 列表。
- 不实现 Plugin 列表。
- 不重新设计 Library UI。

验收：

- 现有 rule source Library 行为不变。
- 非 rule source 不会因为没有 `SiteRule` 崩溃。
- Library 里的 rule-only 访问点被明确限制在 rule source 分支内。

建议测试：

- `RequestConfigUseCaseTests` 中 Library runtime refresh 相关测试。
- 新增一个非 rule source 不崩溃/不伪装 rule 的 ViewModel 级测试，如果测试成本可控。

主要风险：

- Library 是用户最常用路径，不能为架构清理破坏现有 rule source 列表。

## P3-9.4 Reader 规则依赖收窄

目标：Reader 不再天然读取 `source.rule.primaryDetailRequest` / `primaryGalleryRequest`。

当前问题：

- `ReaderViewModel` 仍知道 rule 内部结构。
- 当前 Reader 行为是 rule-specific，但它在 UI 层直接读 rule，边界不够干净。

预计改动：

- rule-backed Reader 行为通过显式 `ruleConfiguration` 或 `RuleSourceRuntime` 内部路径获取。
- 非 rule source 暂时返回 unsupported / 空状态，而不是尝试解析 `SiteRule`。
- 保留现有阅读体验，不做播放器、不做 RSS reader。

不做：

- 不做视频播放器。
- 不做 RSS 阅读器。
- 不重写 Reader UI。

验收：

- rule source Reader 原有 detail / gallery / direct-reader 行为不变。
- ReaderViewModel 对非 rule source 没有隐式 `source.rule` 假设。

建议测试：

- `RequestConfigUseCaseTests` 中 reader/detail/direct-reader 测试。
- 必要时增加 ReaderViewModel 非 rule guard 测试。

主要风险：

- Reader 链路横跨 detail、chapter、gallery、image request，改动要小步。

## P3-9.5 Rule-only UseCase 归位

目标：让 rule-only use case 看起来就是 RuleSourceRuntime 内部实现，而不是共享 runtime 方案。

当前问题：

- `SearchSourceUseCase`
- `LoadReaderChapterUseCase`

这些名字在 `Application/UseCases` 下容易被误解为所有 source runtime 都能复用，但实际上它们高度依赖 `SiteRule` / parser。

预计改动：

- 先审计引用。
- 如果移动成本低，把 rule-only use case 移到 `Application/Runtime/Rule/` 或增加命名前缀。
- 如果移动会引发大范围 churn，则先通过注释 / README / factory 边界明确它们是 rule runtime internals。

不做：

- 不强行重写 use case。
- 不抽象一个空泛的 shared reader/search use case。

验收：

- 新 runtime 不会被引导去复用这些 rule-only use case。
- `RuleSourceRuntime` 内部依赖关系更清楚。

建议测试：

- 编译级验证。
- `SourceRuntimeMappingTests`
- `RequestConfigUseCaseTests`

主要风险：

- 文件移动会触发 XcodeGen，需要控制范围。

## P3-9.6 完整性回归

目标：确认 P3-9 真正拆掉 `Source.rule` 强依赖，而不是只换了名字。

检查项：

- `Source` 是否以 `configuration` 为主字段。
- `SourceRecord` 是否能读 `.rule/.rss/.plugin` config。
- Library / Reader 是否不再默认所有 source 都有 rule。
- Rule-only use case 是否已归位或明确标记。
- 是否无 Bridge / Adapter 命名复发。
- 是否没有把 RSS / video / plugin 字段塞进 `SiteRule`。
- Core 是否仍无 App-only 依赖。

建议测试：

- `SourceRuntimeMappingTests`
- `RequestConfigUseCaseTests`
- 相关 repository / ViewModel tests
- 如移动 Swift 文件，先运行 `./scripts/regenerate-project.sh`

验收结论：

- P3-9 完成后，再决定下一阶段做：
  - RuleSourceRuntime video capability，适合 Yealico 风格规则能表达的视频页；
  - PluginSourceRuntime MVP，适合 JS 签名、动态 token、多接口、反爬等规则难以表达的网站；
  - RSS optional runtime，低优先级。

## 非目标总表

P3-9 不做这些事情：

- 不实现 RSS runtime。
- 不实现视频网站解析。
- 不执行 Plugin。
- 不重写规则编辑器。
- 不重写 Reader UI。
- 不删除 `SiteRule`。
- 不把视频/RSS/Plugin 加成 `SiteRule` 字段。

## 每节完成后的固定汇报要求

每完成一个 P3-9.x 小节，需要列出：

- 当前物理结构快照。
- 偏航检查。
- 是否运行 XcodeGen / pod install / tests。
- 下一小节任务目标。
- 下一小节计划是否需要更新。
