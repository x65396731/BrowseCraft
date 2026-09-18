# BrowseCraft 文档架构审计：对照 fwq 的 C/S/H/E 模式（2026-09-19）

日期：2026-09-19
范围：BrowseCraft App 仓库的 `AGENTS.md`、`README.md`、`docs/`、`Documentation/`、四个包内 `README.md`；
对照基准是 fwq 的 `docs/rules/documentation-architecture.md` 及其配套（`docs/rules/README.md`、`docs/rules/STATUS.md`、
`HANDOFF.md`、`scripts/check_docs.py`）。
方式：只读审计。未改任何文档、未改代码、未 build、未跑测试。所有计数由扫描得出，可零成本复算。

本文是审计与提案，**不是已批准设计**。第 6 节的迁移分阶段需要用户逐阶段裁决后才能执行。

## 1. 结论

BrowseCraft 侧的文档**不缺内容，缺的是形态约束**。12 份文档共 2,489 行 / 211 KB，写得比 fwq 迁移前更克制
（没有 fwq 那种 2,570 行的批次追加章），但四条让 fwq 文档可被机器核对的机制**一条都没有**：

| fwq 的机制 | BrowseCraft 现状 |
|---|---|
| 入口索引（`AGENTS.md` → `docs/rules/README.md` → `STATUS.md`） | **无**。`AGENTS.md` 对 `Documentation/` 与 `docs/architecture.md` 的链接数为 **0** |
| C/S/H/E 四分类与有界合规闭包 | **无**。合同、批次日志、审计纪事、已闭合交接单同级混放 |
| 瞬时状态离开设计文档，集中到 `STATUS.md` | **无**。7 份文档头部带自由文本 `状态：` 行 |
| 条款稳定 ID（一处定义、他处引用）+ 提交前机器闸门 | **无**。15 条硬条款零 ID；4 个 `check-*.sh` 全部只查代码，零份查文档 |

后果不是理论风险，已经发生了（第 5 节）：RSS 于 2026-09-16 从 App 全删，**四处文档至今仍写着 RSS 存在**。

## 2. 现状量化

扫描快照（2026-09-19）：

| 测量项 | 值 |
|---|---|
| `Documentation/` + `docs/` 文档 | 12 份 / 2,489 行 / 211,136 字节 |
| 其中最大一份 | `Documentation/Audit/2026-09-18-code-audit.md` 780 行 / 81 KB = 全部字节的 **38.4%** |
| 带自由文本 `状态：` 头部行的文档 | 7 份 |
| `更新时间/状态/影响范围/前置/问题类型` 一类头部行 | 27 行 |
| 带日期的日志式章节标题（`## …（2026-xx-xx）`） | 28 个，其中 `Book-Kind-Wiring-Design.md` 占 17 个 |
| 正文里的 commit 短哈希 | 20 处，分布在 5 份文档 |
| 硬条款词（`必须`/`不得`/`禁止`/`不允许`）总数 | 73 处（`AGENTS.md` 另有 15 条 bullet） |
| 带稳定 ID 的硬条款 | **0** |
| 引用 fwq 条款 ID 的处数 | 25 处（18 个不同 ID，**全部可在 fwq C 类解析到定义点**） |
| 文档内相对链接断链 | **0**（这一项现状是好的） |
| 查文档的机器闸门 | **0**（`scripts/` 有 6 个脚本、4 个 `check-*.sh`，全部查代码或资产） |

对照：fwq 迁移前 `docs/rules/` 是 15 份 / 7,766 行 / 633 KB，其中 85% 是历史日志。
**BrowseCraft 的体量小一个数量级，现在做迁移的代价远低于 fwq 当时。**

## 3. 文档逐份分类判定

按 fwq `BC-DOC-047` 的四分类（C 合同 / S 状态 / H 历史 / E 证据）对现有 12 份逐份判定。
「混装」指同一份里既有当前有效的合同，又有只记「当时为什么这么改」的日志。

| 文档 | 行 | 判定 | 依据 |
|---|---|---|---|
| `docs/architecture.md` | 256 | **C**（含过期事实） | 全文只用现在时陈述模块、层、不变量；无状态头、无哈希。第 5 节的 RSS 过期点要修 |
| `Documentation/CloudKit/AccountScopedDatabaseMigration-Memo.md` | 56 | **C**（带状态头） | 正文是当前身份边界合同；头部两行状态要出表 |
| `Documentation/Sources/Catalog-Rule-Update-Design.md` | 27 | **C** | 判据、入口、固定输入、实现位置，无状态头、无哈希——**这份最接近目标形态** |
| `Documentation/Sources/Catalog-Same-Site-Entry-Subtitle-Design.md` | 36 | **C** | 同上；末节「真机验证」是状态，要出表 |
| `Documentation/Video/RuntimeAdFilter-Design.md` | 144 | **C 混 H** | 一、二、四、七节是合同；「四之二 实施时被测量推翻的两条默认假设」「四之三 实际落点」「六 验收」是纪事 |
| `Documentation/Book/Local-Book-Import-Design.md` | 124 | **C 混 H** | 一~七节是设计合同；「八 入口已藏」是裁决纪事；头部状态行 5 行、含 B2 教训与备注 |
| `Documentation/Book/Book-Kind-Wiring-Design.md` | 309 | **C 混 H（混得最重）** | 一~七节是合同（85 行）；**八~二十三节共 17 个带日期的落地/倒查记录（224 行 = 72%）是 H** |
| `Documentation/Sources/RSS-Removal.md` | 47 | **H** | 全文是一次性下线的执行记录；唯一仍有约束力的是「保留清单」，该内容属 C |
| `Documentation/Book/Readium-Integration-Handoff.md` | 128 | **H**（已闭合的交接单） | 状态停在 2026-09-13「未 build、未提交」；其第五节「推进顺序」已被 `Book-Kind-Wiring-Design.md` 批次 A–C 执行完 |
| `Documentation/Video/JablePlaybackRule-Handoff.md` | 267 | **H**（已闭合的交接单） | 状态停在 2026-08-21「待更新 Catalog 规则」；其结论已由 fwq `BC-PLAYBACK-049` 承接 |
| `Documentation/CloudKit/Phase0-Data-Contract-and-Security-Audit.md` | 315 | **H 含 C** | 2026-07-22 的一次审计；**文档自己在第 9 行声明部分内容已失效**，另一部分「Cloud payload 安全结论继续有效」——有效的那部分应提升为 C |
| `Documentation/Audit/2026-09-18-code-audit.md` | 780 | **H** | 审计报告 + 修正清单 + 五轮「判定被测量推翻」的纪事，全部是过程事实 |

**结论**：12 份里纯 C 只有 4 份，纯 H 有 5 份，混装 3 份。
H 类合计 1,537 行 = 全部行数的 **61.8%**——与 fwq 迁移前 85% 同性质，只是程度轻。

包内 `README.md`（`Features` / `Domain/Models` / `Application/UseCases` / `Infrastructure/Database`）
与 `scripts/README.md` 都是 C 类且形态干净，本次不动，只修第 5 节点名的过期句。

## 4. 与 fwq 的接缝：App 侧条款**已经有 ID 了，但不在本仓库**

这是本次审计最重要的发现，也是「做成和 fwq 一样的模式」时必须先裁决的事。

fwq 的 `docs/rules/STATUS.md` 里有 **`APP-MEMO-001` ~ `APP-MEMO-016` 共 16 行**，承载的全部是
**BrowseCraft App 侧的实施状态**。例如 `APP-MEMO-016`（本仓库 09-18 实施的漫画阅读页图组判稳、09-19 的
总超时留余量）的定义点在 fwq `docs/rules/video-runtime-acceptance.md`，状态行在 fwq `STATUS.md`，
而实现、固定输入与真机日志在本仓库。

也就是说，**App 侧的约束当前分散在三处，且三处互不索引**：

1. fwq 的 `APP-MEMO-*`：由规则生成引出的 App 改动，**有 ID、有状态枚举、有闸门**；
2. 本仓库 `AGENTS.md` 的 15 条硬条款（SwiftSoup 不得扩散、`responsePolicy` 边界、Readium 只服务读书 kind、
   catalog 包装字段等）：**无 ID、无状态、无闸门**；
3. 本仓库 `Documentation/` 各设计书内嵌的约束：**无 ID、无状态、无闸门**。

第 2、3 类里有一部分与 fwq 的 C 类文档**表达同一条约束**（catalog 外层包装、`responsePolicy` 显式声明、
pipeline 白名单），按 fwq `BC-CLAUSE-004` 这属于「跨文档表达同一约束却有两个定义点」，
正是会漂移的形态。目前还没漂——但没有任何机制阻止它漂。

**已裁决（2026-09-19，用户选「乙」）**：按触发源分域。

- **`APP-MEMO-NNN`（定义点在 fwq）** —— 由规则生成引出的 App 改动。本仓库只写引用点，状态一律指向
  fwq `docs/rules/STATUS.md`，不在本仓库复制状态行。
- **`BCA-<DOMAIN>-<NNN>`（定义点在本仓库）** —— App 内部不变量，与规则生成无关。
  `NNN` 三位十进制，在同一 `DOMAIN` 内单调递增；ID 一经分配永不复用，即使条款被废弃。

`DOMAIN` 受控词表（不得自造；新增域必须先改词表，改词表本身是一次裁决）：

| 域 | 用于 | 现有条款来源 |
|---|---|---|
| `ARCH` | 分层依赖方向、框架泄漏、跨层类型引用、SwiftSoup 容器、APIKit 逃逸 | `AGENTS.md` 第一节、`docs/architecture.md` §3 |
| `BUILD` | XcodeGen、SwiftSoup fork 覆盖、广告配置、Swift 语言模式 | `AGENTS.md` 第一节、`docs/architecture.md` §3、§7 |
| `RUNTIME` | 规则执行边界、请求合并、WebView 加载与判稳、网络载体职责 | `AGENTS.md` 第一节 |
| `PARSE` | `responsePolicy` 的 App 侧职责边界、itemPath 语义、legacy 隔离 | `AGENTS.md` 第一节 |
| `DB` | GRDB 迁移纪律、表与索引的定义位置 | `Infrastructure/Database/README.md` |
| `SYNC` | CloudKit payload 安全门禁、账户作用域、身份边界 | `CloudKit/*` 两份 |
| `BOOK` | Readium 边界、`Locator` 不透明性、本地书容器策略 | `Book/*` 两份 |
| `UI` | Features 层的路由与目的地声明纪律 | `Local-Book-Import-Design.md` B2 教训 |

**三条边界规则**（本身就是条款，进 `BCA-DOC` 域，由 D4 的闸门执行）：

1. 一条约束若在 fwq C 类已有定义点，本仓库**只允许出现引用点**（对应闸门 A3）。
2. 一个 `BCA-*` ID 在本仓库恰有一个定义点，围栏代码块内的不计（对应闸门 A1）。
3. **过程纪律不编号**。`AGENTS.md` 开头「不要主动跑测试」「不要自动 build」这类约束的是会话行为而非代码形态，
   没有第二个定义点的风险，编号只会让 ID 空间充满不可机检的条目。fwq 的 `AGENTS.md` 同样不给它们编号。

**AGENTS.md 第二节的处置（同日裁决）**：那 11 条规则生成合同**逐条改成引用点**——每条保留一行，
只写 fwq 的 ID 加一句本层适用范围，删除复述的正文。保留的理由是 App 仍有
`Features/Sources/RuleSource/RuleJSONEditorView.swift` 这条编辑既有来源规则 JSON 的路，这 11 条在那条路上仍要守；
改成引用点的理由是它们与 fwq `comic-catalog-profile.md` 及正规化合同逐条重叠，按 `BC-CLAUSE-004` 本仓库不是定义点。
逐条找出对应 fwq ID 是一次性工作量（约 11 条），属 D3。

**定义命名空间时顺带发现的一处本仓库内部双定义点**：`AGENTS.md` 第一节的「SwiftSoup 不得扩散到加载链路」
与 `docs/architecture.md` §3 的「SwiftSoup containment in Core」表达同一约束的重叠部分，两处各写一份正文
（前者还额外覆盖 App/Domain/Application）。这正是边界规则 2 要禁止的形态，D3 收口时必须择一为定义点。

## 5. 已发生的漂移（证明第 1 节不是理论风险）

RSS 于 2026-09-16 从 App 五个仓库全部删除，记录在 `Documentation/Sources/RSS-Removal.md`。
代码侧已核对：`BrowseCraftCore` 的 `SourceRuntimeKind` 只剩 `comic / video / plugin / book`
（`Sources/BrowseCraftRuleModels/Source/SourceDefinitionModels.swift`），`BrowseCraftRuntime/Sources/`
只有 `Book / Comic / Common / Video` 四个目录。文档侧仍有四处说 RSS 存在：

| 位置 | 原文 | 事实 |
|---|---|---|
| `docs/architecture.md:16` | Runtime 是「Comic, RSS, Video and the shared dispatch」 | 是 Book / Comic / Video |
| `docs/architecture.md:136` | 「RSS and rule-loading paths go through their boundary protocols」 | RSS 路径不存在了 |
| `BrowseCraft/Application/UseCases/README.md:10,13` | 「`History/`: RSS, comic, and video history」；举例仍用 RSS use case | RSS 历史表与用例已删 |
| `Documentation/Book/Book-Kind-Wiring-Design.md:9` | 「book 是第四种 `SourceRuntimeKind`（comic / rss / video / plugin 之后）」 | 枚举里没有 rss |

另一类漂移风险是**写死的过程数字**。`Documentation/Video/RuntimeAdFilter-Design.md:3-4` 的状态行写着
「Swift Testing 353 项 / 58 suites + XCTest 27 项，0 失败」——按 fwq `BC-DOC-002a` 这是禁止形态，
因为除了重跑一次全量测试，**没有任何办法判断这三个数字今天是否仍成立**。同理，
`Documentation/Video/JablePlaybackRule-Handoff.md` 的状态停在 2026-08-21「待更新 Catalog 规则」，
而该结论早已由 fwq `BC-PLAYBACK-049` 承接并实施——读这份文档的人会以为还有待办。

**这四处 + 两类，是零成本可复算的迁移前基线。**

## 6. 迁移提案（分阶段，每阶段单独裁决）

原则三条，与 fwq 的做法一致：

- **只搬不改**。每一阶段要么只移动文件、要么只抽取状态，**不改任何一条约束的语义**。
  发现冲突时停下上报，不在迁移中顺手改语义。
- **零代码改动**。全部阶段不碰一行 Swift，影视线与漫画线不受影响，无需真机复核。
- **先固化再演进**。把今天的取值先写成闸门基线，之后的漂移才能被检出。

### D0：冻结基线（零成本，不动任何文件）

把第 2 节的量化表、第 3 节的逐份判定、第 5 节的四处漂移记为迁移前基线（即本文）。
D1 之后任何一项数字变化都应有对应的阶段说明。

### D1：建索引 + 只移动文件

目标目录形态（与 fwq 同构）：

```
AGENTS.md           # 入口纪律；只写引用点，链到 docs/README.md
HANDOFF.md          # 会话入口（H 类），见 D5
docs/README.md      # C 类索引 + 合规闭包定义 + 按任务读取路径
docs/STATUS.md      # 唯一瞬时状态承载，见 D2
docs/architecture.md
docs/design/*.md    # C 类设计合同（从 Documentation/ 迁入）
docs/history/*.md   # H 类归档（批次记录、审计纪事、已闭合交接单）
```

本阶段只做三件事，**一个字都不改**：

1. 5 份纯 H 文档整份移入 `docs/history/`（`RSS-Removal`、两份 `*-Handoff`、`Phase0-*-Audit`、`2026-09-18-code-audit`）；
2. 4 份纯 C 文档移入 `docs/design/`；
3. 3 份混装的**先整份移入 `docs/design/`**，拆分放到 D3，避免同一阶段既移动又改写。

同时新建 `docs/README.md`（索引 + 闭包定义）并在 `AGENTS.md` 顶部加一行链接——
这一条单独就解决了第 1 节表里的第一行。

**零成本验证**：`git mv` 后全库 grep 旧路径，断链数应为 0（当前断链已是 0，是可比基线）。

### D2：状态出设计文档

7 份文档的 `状态：` 头部行 + 3 份文档末尾的「验证/真机」节 → `docs/STATUS.md` 表格行。
列与取值枚举直接沿用 fwq `documentation-architecture.md` 第 5 节（决策 / 设计 / 实施 / 验证 / 检查点 / 更新日期），
**每格恰一个值，不得用 `/` 拼接自由文本**。

需要用户裁决一件事：fwq 的 `APP-MEMO-*` 行已经在承载一部分 App 状态。
本仓库的 `STATUS.md` 应当是**只放第 4 节「乙」方案里的 App 内部条款**，
对 `APP-MEMO-*` 只写一行指针「状态见 fwq `docs/rules/STATUS.md`」，不复制。否则又是两处定义。

### D3：条款编号与混装拆分

1. 按第 4 节裁决的命名空间，给 `AGENTS.md` 的 15 条硬条款与设计书里的硬条款分配 ID，行首反引号定义点形态；
2. 凡在 fwq C 类已有定义点的约束，本仓库改为**只写 ID 的引用点**，删除复述的正文；
3. 拆 3 份混装文档：`Book-Kind-Wiring-Design.md` 的八~二十三节（224 行）、
   `RuntimeAdFilter-Design.md` 的四之二/四之三/六节、`Local-Book-Import-Design.md` 的第八节
   移入 `docs/history/`，C 类正文只留现在时的合同。

### D4：机器闸门 `scripts/check-docs.sh`

**不照搬 fwq 的 16 项**——BrowseCraft 没有 `STATUS.md` 的检查点列历史包袱，也没有 137 份归档。
按本仓库实测到的问题，首版只做 8 项，每一项都对应第 2、5 节里一个已量到的形态：

| # | 检查 | 对应本文 |
|---|---|---|
| A1 | 每个本仓库 ID 恰有一个定义点 | 第 4 节 |
| A2 | 引用的 ID 存在（本仓库定义点 ∪ fwq C 类定义点） | 第 4 节、25 处跨仓引用 |
| A3 | 本仓库不得为 fwq 已定义的 ID 写定义点 | 第 4 节「乙」的边界规则 |
| A4 | C 类无自由文本状态头部行 | 第 2 节 27 行 |
| A5 | C 类无 commit 哈希、无 `N 项 / N suites` 形态的测试计数 | 第 2 节 20 处、第 5 节 |
| A6 | C 类无带日期的日志式章节标题 | 第 2 节 28 个 |
| A7 | 相对链接可解析，无绝对主机路径 | 当前 0 断链，固化住 |
| A8 | `STATUS.md` 每格取值落枚举、无 `/` 拼接 | D2 |

跨仓的 A2/A3 需要 fwq 路径可达。fwq 侧不在时应**跳过并如实报告跳过**，不得静默通过——
这是闸门本身的诚实性要求，写进脚本注释。

闸门接线位置待裁决：加进 `scripts/check-architecture-boundaries.sh` 所在的 pre-build 阶段（改文档也要 build 才知道），
还是只在提交前手动跑（与 fwq 的 `check_docs.py` 同构）。**建议后者**——文档闸门失败不应阻断代码 build。

### D5：`HANDOFF.md` 会话入口

本仓库当前**没有会话入口**。两份叫「交接」的文档都是单主题交接单且已闭合，
当前进展只能从 `git log` 与 fwq 的 `HANDOFF.md` 里反推。

按 fwq `BC-DOC-056` 的形态建根 `HANDOFF.md`：只承载四样东西——当前状态快照（现查口径的命令，不记数字）、
未选候选与挂账的指针、环境与命令速查、归档索引；**不承载条款定义点，不复述定义点正文**。

需要裁决：fwq 的 `HANDOFF.md` 已经在记 App 侧的真机与部署进展（`APP-MEMO-016` 那一长段即是）。
本仓库的 `HANDOFF.md` 若也记，同一件事会有两份流水。建议本仓库的 `HANDOFF.md` 只记
**纯 App 侧的工作**（分层重构、警告清零、Swift 6、资产瘦身、Readium、book 接线），
规则生成引出的改动仍在 fwq 侧记，本仓库只留指针。

### 阶段依赖

D0 → D1 → D2 → D3 → D4，D5 可与 D2 之后任意阶段并行。
D4 必须在 D3 之后，否则闸门会对尚未拆分的混装文档整片报红。

## 7. 本审计没有做的事

- 未读 `BrowseCraftCore/Documentation/` 的 10 份文档正文（375 + 104 + 171 + 69 + 62 + 134 + 256 + 71 + 938 + 444 行）。
  仅从文件名可见 `Phase0/1/2/3/4/6`（`Phase5RSSParsingMigration.md` 已随 RSS 下线删除，序号留洞）
  是迁移历史、属 H 类，却与 `CoreParsingBoundary.md` 这类当前合同同级混放——
  **Core 仓库有同一个问题，规模比 App 仓库更大（2,624 行）**。是否一并迁移需用户裁决。
  `BrowseCraftDomain` / `BrowseCraftRuntime` / `BrowseCraftAPIKit` 各只有一份 `README.md`，问题不大。
- 未核对各设计书正文与当前代码是否逐条一致。本文只核了 RSS 一处（因为它是全仓库范围的删除，可零成本判定）。
  逐条核对属 fwq `BC-DOC-028`（文档点名的模型必须在代码中存在）那一类，代价远高于本次审计，应另行立项。
- 未改任何文件。
