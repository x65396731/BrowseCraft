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
