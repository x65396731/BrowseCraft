# 状态变更流水

本文属 H 类（`BCA-DOC-009`），**只追加，不修改**。它不构成生产约束，不参与逐条核对，
不得被引用为实施依据。它保存两类内容：

1. 被 [STATUS.md](../STATUS.md) 覆盖的旧值，格式为「日期 + 工作项 + 旧值 → 新值 + 原因」；
2. 按 `BCA-DOC-007` 三分法从 C 类文档搬出的叙事事实——某日跑了什么、拿到什么结果、哪次提交做了什么。

第 2 类一律**逐字保留原文**，不改写（`BCA-DOC-008`）。原文里标 `〔留在 C 类〕` 的位置，
是同段中仍然有效的约束或范围声明句，按三分法留在了原设计文档里。

## 2026-09-19 D2：四份 C 类文档的状态段落与两处验证节分流

搬出的原文逐段抄录如下。每段注明它来自哪份文档的哪个位置，以及归约后落在 `STATUS.md` 的哪些行。

### 读书 kind（book）App 侧接线 —— 原 `docs/design/Book-Kind-Wiring-Design.md` 标题与头部

归约去向：`STATUS.md` 第 1 节「读书 kind App 侧接线立项」「批次 A」「批次 B」「批次 C」
「站点有声作品的播放器」「四个接口变体」六行。

```text
# 读书 kind（book）App 侧接线（立项，待拍板）

更新时间：2026-09-13
状态：**批次 A、B、C 已落地（2026-09-14）**；有声作品的播放器与四个接口变体另立项；〔留在 C 类〕。〔留在 C 类〕
〔留在 C 类〕
前置：服务器接线已部署（PortalCore `b9fc2ff`，2026-09-13 深夜），`POST /v1/rule-generations` 已接受 `sourceKind: book`；Readium 3.11.0 依赖已入库（BrowseCraft `7ad27044`），**首次整包 build 已于 2026-09-13 深夜通过**（`xcodebuild -scheme BrowseCraft` 模拟器 iPhone 16 Pro，0 error；影视线与漫画线的真机复核仍待用户）
```

### 本地书籍导入与 Readium 阅读器 —— 原 `docs/design/Local-Book-Import-Design.md` 标题与头部

归约去向：`STATUS.md` 第 1 节「本地书籍导入 B0 / B1 / B2 / B3」「本地导入入口已藏」
「Readium Swift Toolkit 3.11.0 选型」六行。

```text
# 本地书籍导入与 Readium 阅读器（设计，待拍板）

更新时间：2026-09-13
状态：**B0、B1、B2 已落地，入口已藏**（2026-09-13 ~ 09-14）。**用户 2026-09-14 裁决：App 不对用户暴露本地导入**——Library 工具栏的「书籍」入口与书架装配已去掉，〔留在 C 类〕；〔留在 C 类〕。B2 在模拟器上走通了导入 → 书架 → 阅读器 → 目录跳转 → 书签 → 退出重开续读（iPhone 16 Pro），**真机验收仍待用户**。〔留在 C 类〕。〔留在 C 类〕
〔留在 C 类〕
前置：Readium 3.11.0 依赖已入库且首次整包 build 已通过（2026-09-13，0 error）；影视线与漫画线的真机复核仍待用户
```

### Identity 数据归属与数据库策略备忘 —— 原 `docs/design/AccountScopedDatabaseMigration-Memo.md` 头部

归约去向：`STATUS.md` 第 4 节「身份边界切换到 Sign in with Apple 与后端生成的 AppUser UUID」一行。

```text
# Identity 数据归属与数据库策略备忘

更新时间：2026-07-28
状态：已切换到 Sign in with Apple 与后端生成 AppUser UUID
```

### 运行期广告过滤承接规则匹配结果 —— 原 `docs/design/RuntimeAdFilter-Design.md` 头部

归约去向：`STATUS.md` 第 3 节「运行期广告过滤承接规则匹配结果」一行。

```text
# 运行期广告过滤承接规则匹配结果（设计）

更新时间：2026-08-29  
状态：**已实施并验证**——`BrowseCraftTests` 全目标通过
（Swift Testing 353 项 / 58 suites + XCTest 27 项，0 失败），含本设计新增的 9 项判定用例  
〔留在 C 类〕  
〔留在 C 类〕
```

### 运行期广告过滤的验收读数与命令 —— 原 `docs/design/RuntimeAdFilter-Design.md` 第六节

归约去向：同上一行的 `实施=implemented` / `验证=full-suite-passed`。
这段里的测试计数（Swift Testing 353 项 / 58 suites + XCTest 27 项）是 2026-08-29 当次的读数，
**此后未重新核对**：按 `BCA-DOC-008` 它逐字保留在此，但不得被当作当前事实复述。

```text
## 六、验收

- App 侧：9 项用例（`SourceContentNoiseFilterTests` 4 项、
  `VideoSourcePlaybackLoaderTests` 5 项）**全部通过**，〔留在 C 类〕
  同一次运行里 `BrowseCraftTests` 全目标通过（Swift Testing 353 项 + XCTest 27 项），
  既有噪声过滤与播放 loader 用例无回归，改动文件零编译警告。

  `xcode-select` 指向 CommandLineTools，用环境变量覆盖即可，不需要 sudo：

  ```bash
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,id=C612B32B-9D17-4C9A-B82E-8036D535E59F' -derivedDataPath .derivedData -only-testing:BrowseCraftTests
  ```
- 后端侧：取消排除要求后 `jable.tv` 与 `kpkuang.org` 复跑，
  分别报告 `normalizationStatus` 与 `runtimeValidationStatus`。
- 上述用例已跑通，规则仓库的 `APP-MEMO-008` 现记实施 `implemented` /
  验证 `full-suite-passed`，**本项对发布的阻塞已解除**。〔留在 C 类〕
  〔留在 C 类〕

```

### 同站多条来源的副标题 —— 原 `docs/design/Catalog-Same-Site-Entry-Subtitle-Design.md` 第五节

归约去向：`STATUS.md` 第 2 节「同站多条来源的副标题显示各自入口地址」一行的 `验证=device-passed`。

```text
## 五、真机验证

2026-09-15 用户真机确认：规则目录里两条 sfacg 副标题分别显示 `https://book.sfacg.com/List/` 与
`https://book.sfacg.com/List/?tid=21`，动漫嗨手写 / 生成两条也能区分。
```

## 2026-09-19 D2：被 STATUS.md 覆盖的旧值

本轮是 `STATUS.md` 的首次建立，没有被覆盖的旧值。此后每次改状态格，按
`BCA-DOC-006` 在本节追加一行。

## 2026-09-19 D3：本地导入入口已藏的裁决原文

原 `docs/design/Local-Book-Import-Design.md` 第八节开头，逐字保留。该节的「去掉 / 保留 / 不做 / 迁移不回退」
四条是仍然有效的范围声明，按 `BCA-DOC-007` 留在了原设计文档。归约去向：`STATUS.md` 第 1 节
「本地导入入口已藏」与「本地书籍导入 B3」两行。

```text
用户在 B2 落地后问「为什么有本地存储的功能，这个功能和漫画有什么关系」：本地导入来自交接单第五节的建议顺序，与漫画无关，也不涉及规则生成，
对主线（通用网站规则生成 → App 消费 book catalog）只是垫脚石。裁决：**保留代码、去掉入口**。
```

## 2026-09-19 D3：本地书籍导入立项前的 App 现状

原 `docs/design/Local-Book-Import-Design.md` 第二节「App 现状」，逐字保留。它记的是 2026-09-13 的代码形状，
**不是当前事实**：B1 之后 App 有了 `fileImporter`，`RSSReadingHistoryRecord` 已随 RSS 于 2026-09-16 删除。

```text
### App 现状

- **没有任何文件导入入口**（全仓无 `fileImporter` / `UIDocumentPicker`）。
- 阅读历史按 kind 各一张表（`ComicChapterHistoryRecord` / `RSSReadingHistoryRecord` / `VideoWatchHistoryRecord`），Domain 用 `ReadingHistoryEntry.Kind`（`rss / comic / video / temporary`）聚合；漫画的续读位置存 `lastReaderPageURL`。
- 数据库只经 `AppDatabaseMigrations` 追加 `vN.描述` 迁移演进，`AppDatabaseSchemaSnapshotTests` 比对 `sqlite_master` 快照——**加表必须同时更新快照**。数据库文件在 `Application Support`。
- 分层不变量由 `scripts/check-architecture-boundaries.sh` 在预构建阶段强制：Domain / Application 禁框架 import，`BrowseCraftAPIKit` 只许 Infrastructure 与 `AppContainer`，跨层类型引用按层名扫描。
- 阅读器入口：`Features/Library/Comic/Reader/ReaderView`，由 `LibraryView`、`ComicDetailView`、`HistoryView` 三处打开；视频播放在 `Features/Library/Video/Player/`。
- Library 的分流轴是 `Source.configuration.kind`（`SourceRuntimeKind`），本地书不在这条轴上。
```

## 2026-09-19：测试计数差异的核对结论——没有回归，基线取错了

2026-09-19 在 iPhone 17 Pro / iOS 26.5 上跑通 `BrowseCraftTests` 后，读数是
Swift Testing 503 项 / 88 套、XCTest 66 项、48 项跳过，全部 0 失败。我当时说它与
「517 项 / 89 组 + XCTest 39 项」对不上，并把那个数字记成了 2026-09-18 代码审计的记录。

**两处都要更正。**

其一，出处不是审计。审计全文没有「517」。那个数字在
`docs/history/Book-Kind-Wiring-batch-records.md` 第二十三节，记的是 **2026-09-15**
（站点书进 History 页，提交 `79512a9`）当时的状态。

其二，不是回归，是我拿了 RSS 下线之前的基线去比。按 `BrowseCraftTests` 的静态计数逐版核对：

| 版本 | `@Test` | `func test` |
| --- | --- | --- |
| `79512a9`（2026-09-15） | 517 | 39 |
| `f263274`（2026-09-16，RSS 下线后） | 493 | 39 |
| `067759e`（2026-09-18 末） | 503 | 66 |
| 2026-09-19 HEAD | 503 | 66 |

静态计数与运行读数逐项吻合。三段变化各有出处：517 → 493 是 RSS 下线删掉了 RSS 用例；
493 → 503 是 09-18 审计那轮新增；39 → 66 的 27 项来自 09-18 新建的七个 XCTestCase 文件
（就绪选择器 3 + 2 + 5、DOM 判稳 4、图组安定 8、随包动画与图片资产 4 + 1，合计恰为 27）。

`067759e` 到 2026-09-19 HEAD 之间，`BrowseCraftTests` 只有 `ViewModelTestHarness.swift`
改了 4 行（摘掉两个注入参数），**用例零增删**。因此 2026-09-19 的读数就是 09-18 收工时的状态，
规则编辑下线与那 207 行死代码清理没有引入任何行为回归。

**这件事的教训**：复述一个测试计数之前，先确认它是哪个提交上的读数。
`HANDOFF.md` 开头「任何状态性数字在复述前必须现查，不得照抄本文」讲的就是这个，
而我这次照抄的是一份 H 类归档里更早的数字，还把出处记错了一层。

## 2026-09-19：CloudKit 阶段 0 审计的安全结论提升为 C

2026-07-22 的阶段 0 审计一直在 `docs/history/` 里，而它的安全策略是活的合同，实现也已落地——
设计与实现各说各话，谁算数没人知道。本轮逐条对照代码核实后提升：

- 第 5 节「明确排除的数据」→ `BCA-SYNC-009`。核实依据：`SourceCloudPayload` 与
  `FavoriteItemCloudPayload` 的字段表里没有 Cookie、token、历史、StoreKit 交易或缓存。
- 第 6 节「冲突与删除合同」→ `BCA-SYNC-010`。核实依据：`max(updatedAt, deletedAt)` 真在
  `SourceRecord.swift:112` 与 `FavoriteItemRecord.swift:59`；`ifServerRecordUnchanged`、
  `savePolicy`、`tombstone`、`CloudSyncCoordinator`、`sync_queue` 在代码里都有。
- 第 3.1 节里「动态引用可留、解析后的 credential 值绝不写回」一条 → `BCA-SYNC-011`。

**没有提升的部分**：第 3.2、3.3 节的 Header 名称拦截与字面量全面扫描。它们没有实施，
把未实施的东西提升为 C 类条款就是制造一条假合同。改为在同一节显式声明收窄事实、依据与
改回去的前置条件。第 4 节的身份记录合同（约 115 行）与 PortalCore 接口只读审计带日期和
commit 哈希，属纪事，留在归档。

按 `BCA-DOC-009`，`Phase0-Data-Contract-and-Security-Audit.md` 一字未改。

## 2026-09-19：F2-3 后半（`ImagePrefetcher` 预取）结案

| 列 | 旧值 | 新值 |
| --- | --- | --- |
| 决策 | `optional` | `rejected` |
| 设计 | `approved` | `superseded` |

原因：该项自 2026-09-18 起一直挂 `not-started`，但没有人打算做，也没有测量支持它值得做——
`LazyVGrid` 本就提前实例化下一屏单元格、`LazyImage` 随之开始加载，显式 `ImagePrefetcher`
的增量收益从未测到，实现上还要在单元格之外再引入一层预取调度。`ImagePrefetcher` 在全仓零引用。

按 `STATUS.md` 第 0 节的纪律，这种应当明确记成不做，而不是留在 `not-started` 里，
否则几天后会被当成待办重新捡起——该节点名的两次踩坑就是这么来的。

## 2026-09-19 规则编辑下线遗留死代码第二批

新增工作项「规则编辑下线遗留死代码第二批」（`af2e331`），不覆盖 2026-09-19 的第一批那行——
两批清的是不同文件，按 `BCA-DOC-005` 各占一行。

第一批（`4527def`）清的是规则编辑视图那五个文件 207 行。设计书与代码一致性核验发现
Application 层还剩一整条零 UI 入口的链：`UpdateSourceRuleUseCase` 生产侧零引用、
`UpdateVideoSourceConfigurationUseCase` 连测试都没有、`RulePackageExport` 一族与
`SourceRuleEditingCoordinator` 的 duplicate / export / importPackage 三个方法同样零入口，
`SourceRuleEditorService` 还带着一个从未被使用的 `ruleValidator` 字段。两个测试文件
（`RuleManagementUseCaseTests` / `RulePackageUseCaseTests`）钉的全是这些用例，其中
`duplicateSourceCreatesEditableUserRule` 钉的正是「复制产生可编辑用户规则」。

`BCA-UI-003` 本身没有被违反——这条链没有任何 View 入口，用户看不到创建或编辑规则的地方；
清它的理由是「App 里不应当还存在能造出新规则的代码路径」，以及 `SourceRuleEditorService`
这个名字在只剩只读格式化之后会误导下一个读它的人，因此改名为 `SourceRuleDebugJSONFormatter`。

验证只做到 `static-audit-passed`：xcodegen 重新生成工程、架构边界与文档闸门都过、被删符号
全仓零残留的 grep 复核。按 `AGENTS.md` 的会话纪律未 build、未跑测试。

## 2026-09-19 第二批死代码清理的验证升级

工作项「规则编辑下线遗留死代码第二批」

| 列 | 旧值 | 新值 |
| --- | --- | --- |
| 验证 | `static-audit-passed` | `full-suite-passed` |

原因：清完代码时按 `AGENTS.md` 的会话纪律没有 build、没有跑测试，只做到静态核对；
用户随后明确要求 build 与测试，两项都跑了。

`xcodebuild build`（iPhone 17 Pro / iOS 26.5）`BUILD SUCCEEDED`，零警告，构建过程清掉了
`SourceRuleEditorService` 与 `SourceRuleEditingCoordinator` 的 stale 产物。
`xcodebuild test -only-testing:BrowseCraftTests` 通过 559、失败 0、跳过 0，
其中 Swift Testing 493 项 / 86 套。四个包 `swift test` 全过：Domain 5、APIKit 33、
Runtime 10、Core 228（4 跳过）。

App 侧用例数从 503 / 88 套降到 493 / 86 套，**少的正好是删掉的两个测试文件**
（`RuleManagementUseCaseTests` / `RulePackageUseCaseTests`）里的 10 项、2 套，
XCTest 的 66 项不受影响——不是回归。测试期间有一条 QoS 优先级反转的运行期告警，
是既有现象，与本次删除无关。

## 2026-09-30：公共目录来源由手动「更新」改为跟随目录自动覆盖

`STATUS.md` 第 2 节两行被覆盖：

- 「已添加来源的「更新规则」入口」：required / approved / implemented / full-suite-passed / a8a9d5b / 2026-09-14
  → rejected / superseded / reverted / not-run / 175847d / 2026-09-30。
- 「目录刷新时静默覆盖本地规则——先给显式入口，量到需求再考虑自动」：rejected / approved / not-started / not-run / a8a9d5b / 2026-09-14
  → 改名「已添加来源跟随目录自动更新」，required / approved / implemented / not-run / 175847d / 2026-09-30。

原因：规则目录页重设计时用户指出，推荐由服务器给、每次刷新都是最新的，不应再让用户手动点「更新」。
2026-09-14 拒绝自动覆盖的理由是「用户看不见发生了什么，出问题无从倒查」；此后规则编辑入口已全部下线（`BCA-UI-003`），
本地副本不可能被用户改过，自动覆盖不丢任何用户数据，倒查改由日志承担。个人规则此前已按同一原则自动覆盖
（`refreshPersonalSourcesFromOutcomes`，2026-09-22 用户裁定），两条路径由此一致。

实施只做到代码与单测改写：按 `AGENTS.md` 的会话纪律未 build、未跑测试，验证列记 `not-run`。
检查点列记改动所基于的提交。

## 2026-09-30：公共目录来源自动更新的验证

`STATUS.md` 第 2 节「已添加来源跟随目录自动更新」：验证 not-run / 检查点 175847d → targeted-passed / 3646c2e。

原因：用户要求 build 与测试。`xcodebuild build`（iPhone 17 Pro / iOS 26.5）`BUILD SUCCEEDED`，0 error，
构建阶段的本地化检查通过（删掉的 `catalog_update_rule` 没有残留引用）。
`xcodebuild test -only-testing:BrowseCraftTests`：Swift Testing 522 项 / 90 套全过，
含 `catalogSourceWithNewerRuleOffersAnUpdateAndAppliesItInPlace` 与新增的 `addedSourcesFollowTheCatalogWithoutATap`；
XCTest 81 项中 17 处断言失败，全部来自同一个 `BundledImageAssetTests.testEveryDeclaredImageAssetDecodesAtItsDeclaredPixelSize`——
声明为 `multi-scale-png` 的底栏与设置图标在 3x 模拟器上解出 3 倍像素（如 75x75 对声明的 25x25），
测试按单档资产 scale 为 1 计算像素。本次改动不涉及任何资产与该测试，失败与本次无关，
因此验证列记 `targeted-passed` 而非 `full-suite-passed`。xcodebuild 在两套测试跑完后卡在收尾，手动终止。

## 2026-09-30：规则目录页方案 A 开始实施

`STATUS.md` 第 2 节「规则目录页重设计」：设计 draft / 实施 not-started / 检查点 175847d
→ approved / implemented / 9c03d27。

原因：用户选定方案 A 并要求实施。实现与设计稿的两处出入已改回设计文档：未登录页不另设登录按钮，
改为指向设置页的一句指引（登录入口在设置页，目录页不跨功能导航）；「我的生成」空状态不再附保留期说明。
按 `AGENTS.md` 的会话纪律未 build、未跑测试，验证列记 `not-run`；检查点列记改动所基于的提交。

## 2026-09-30：规则目录页方案 A 的验证，与随包图标尺寸测试的修正

`STATUS.md` 第 2 节「规则目录页重设计」：验证 not-run → full-suite-passed（检查点仍记改动所基于的 9c03d27，
本次改动与该行在同一次提交里落地）。

原因：用户要求 build 与测试并修正 XCTest。`xcodebuild build`（iPhone 17 Pro / iOS 26.5）`BUILD SUCCEEDED`，
构建阶段的本地化检查通过。第一次跑 `-only-testing:BrowseCraftTests`：Swift Testing 527 项 / 91 套全过
（含新增的 `CatalogPersonalTimelineTests` 5 项），XCTest 仍是既有的 17 处失败，全部来自
`BundledImageAssetTests`——声明为 `multi-scale-png` 的图标，声明列写的是 @1x 像素（即 pt 尺寸），
测试却一律按「size × scale」比像素，3x 模拟器上必差 3 倍。修正为按形态比较：单档比像素，多档比 pt；
`scripts/README.md` 的对应说明同步改写。修正后整套重跑：Swift Testing 527 项全过，XCTest 81 项 0 失败，`TEST SUCCEEDED`。

## 2026-09-30：推荐卡片展示字段的线上实测

为决定推荐卡片展示哪些规则信息，在目录加载时临时统计了规则本体里各字段的有值比例（只写日志，落地后已删）。
用户在 Debug 构建上打开规则目录得到的读数：

| kind | 条数 | ≥2 个分类 | 分类数上限 | 可搜索 | 有语言 | 语言分布 | 有站点图标 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| video | 7 | 5 | 11 | 3 | 6 | en:1, es:1, ja:1, zh-Hans:3 | 0 |
| comic | 5 | 2 | 2 | 4 | 5 | en:1, ja:1, zh-Hans:3 | 0 |
| book | 11 | 8 | 20 | 6 | 10 | cmn-Hans-HK:1, cmn-Hant-TW:1, en:1, zh-Hans:5, zh-Hant:2 | 0 |

据此卡片展示分类、可搜索与语言（与界面语言不同时），不展示站点图标；登录需求按用户裁定不展示。
同为中文出现 `zh-*` 与 `cmn-*` 两种写法，展示前按文字归一为简 / 繁。
