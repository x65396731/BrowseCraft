# BrowseCraft 文档索引

本目录是 App 仓库文档的唯一入口。`docs/design/` 与本文、[architecture.md](architecture.md) 保留当前可执行的规范与
设计约束；`docs/history/` 只保存批次记录、审计纪事与已闭合的交接单。文档的组织形式、条款标识与状态承载由第 3–5 节定义。

## 1. 合规闭包

「给出架构或代码修正建议前必须逐条核对适用设计文档」的范围是有界的：

| 类 | 位置 | 在闭包内 | 时态 |
| --- | --- | --- | --- |
| **C 合同** | `AGENTS.md`、`docs/README.md`、`docs/architecture.md`、`docs/design/*.md`、包内 `README.md` | **是** | 只用现在时陈述 |
| **S 状态** | `docs/STATUS.md` | **仅该工作项对应的行** | 受控枚举 |
| H 历史 | `docs/history/*.md` | 否 | 只追加，不修改 |
| E 证据 | 真机日志、构建日志、测试产物 | 否 | 只追加 |

- `BCA-DOC-011` 仓库根的 [`HANDOFF.md`](../HANDOFF.md) 是会话入口，属 H 类。它只承载四样东西：
  当前状态的现查口径、未选候选与挂账的指针、环境与命令速查、归档索引。它**不承载条款定义点，
  也不复述定义点正文**，并且只记「怎么查」而不记状态性数字——那些数字照抄必然过期。
  它不适用第 3 节的 C 类形态约束。规模上限是**信号而非精确边界**：只许承载那四样，规模因此有自然上限，
  超限说明它又开始承载别的东西了。阈值的唯一声明点在 `scripts/check-docs.py`，本文不复述数值——写两处必然漂移。
- `BCA-DOC-009` `docs/history/` 不构成生产约束，不参与逐条核对，不得被引用为实施依据。它只保存「当时为什么这么改」
  的事实，只追加、不修改。把其中任何文本恢复为约束，必须重新走批准流程并写入 C 类文档。

- `BCA-DOC-010` 本节与第 4、5 节的规则由 `python3 scripts/check-docs.py` 执行。改动任何 C 类文档、
  `docs/STATUS.md` 或 `AGENTS.md` 后，提交前必须跑一次；任一项失败即不得提交。它**不接进 pre-build**——
  文档闸门失败不应阻断代码 build。跨仓的 A2、A3 在 fwq 不可达时跳过并如实报告跳过，不得静默通过。

## 2. 权威层级

发生冲突时按以下顺序处理：

1. 当前 BrowseCraftCore 的 Swift 模型、严格校验器、resolved graph 与 parser 定义内层运行时合同；
   `BrowseCraftCore/docs/design/CoreParsingBoundary.md` 是 Core 可做什么的权威陈述。
2. 本目录的 C 类文档定义 App 侧的架构与实施约束。
3. fwq 仓库 `docs/rules/` 定义规则生成与 catalog 发布规范。App 侧只引用，不复述（见第 4 节）。
4. 真机日志与构建产物只证明当时观察到的事实。

## 3. C 类文档的形态

- `BCA-DOC-012` C 类文档不得出现：自由文本的状态串头部行（`状态：…`、`更新时间：…`）；带日期的日志式章节标题；
  commit 短哈希；`N 项 / N suites` 形态的测试计数。瞬时状态一律进 `docs/STATUS.md`，过程事实一律进 `docs/history/`。
- `BCA-DOC-013` C 类文档内的链接必须使用仓库相对路径，禁止绝对主机路径。
- `BCA-DOC-014` C 类文档反引号内点名的类型、协议与家族通配必须在源码里真的存在。确属外部 SDK、
  plist 键、占位记号或有意提及的已删符号时，登记到 `scripts/docs-external-symbols.txt`；
  该表**只允许收敛、不允许新增未经审阅的条目**。

这四类内容随代码演进必然过期，且无法在不重跑的前提下判断真伪。`RuntimeAdFilter-Design.md` 的头部曾写死这样一行：

```text
状态：**已实施并验证**——`BrowseCraftTests` 全目标通过
（Swift Testing 353 项 / 58 suites + XCTest 27 项，0 失败）
```

除了重跑一次全量测试，没有任何办法判断这三个数字今天是否仍成立。原文按 `BCA-DOC-007` 已移入
[history/status-log.md](history/status-log.md)。

## 4. 条款稳定 ID

App 侧的硬条款按**触发源**分属两个命名空间：

- **`APP-MEMO-<NNN>`** —— 由规则生成引出的 App 改动。**定义点在 fwq** `docs/rules/`，状态行在 fwq `docs/rules/STATUS.md`。
  本仓库只写引用点，不复述正文，不复制状态。
- **`BCA-<DOMAIN>-<NNN>`** —— App 内部不变量，与规则生成无关。**定义点在本仓库**。`NNN` 为三位十进制，
  在同一 `DOMAIN` 内单调递增；ID 一经分配永不复用，即使该条款被废弃。

`DOMAIN` 受控词表（不得自造；新增域必须先改本表，改本表本身是一次裁决）：

| 域 | 用于 |
| --- | --- |
| `ARCH` | 分层依赖方向、框架泄漏、跨层类型引用、SwiftSoup 容器、APIKit 逃逸 |
| `BUILD` | XcodeGen、SwiftSoup fork 覆盖、广告配置、Swift 语言模式 |
| `RUNTIME` | 规则执行边界、请求合并、WebView 加载与判稳、网络载体职责 |
| `PARSE` | `responsePolicy` 的 App 侧职责边界、itemPath 语义、legacy 隔离 |
| `DB` | GRDB 迁移纪律、表与索引的定义位置 |
| `SYNC` | CloudKit payload 安全门禁、账户作用域、身份边界 |
| `BOOK` | Readium 边界、`Locator` 不透明性、本地书容器策略 |
| `UI` | Features 层的路由与目的地声明纪律 |
| `DOC` | 本文定义的文档架构自身规则 |

三条边界规则：

- `BCA-DOC-001` 一条约束若在 fwq 的 C 类文档已有定义点，本仓库**只允许出现引用点**。引用点只写 ID，
  可补充「在本层的适用范围」，不得复述、改写或摘要定义点正文，也不得补充或收紧约束本身。
- `BCA-DOC-015` 承载条款定义点的文档必须被 git 跟踪。不被跟踪的文档（如 `.gitignore` 掉的 `AGENTS.md`）
  只能写引用点——它在别的机器上根本不存在，把条款正文放进去等于那条合同不在仓库里。
  这条不禁止 C 类文档不被跟踪，只禁止不被跟踪的文档承载定义点。
- `BCA-DOC-002` 一个 `BCA-*` ID 在本仓库恰有一个定义点。定义点写在行首，ID 用反引号包裹，其后是完整条款正文；
  围栏代码块内的 ID 是语法示例，不计为定义点也不计为引用点。
- `BCA-DOC-003` **过程纪律不编号。** `AGENTS.md` 开头「不要主动跑测试」「不要自动 build」这类约束的是会话行为
  而非代码形态，没有第二个定义点的风险；给它们编号只会让 ID 空间充满不可机检的条目。

条款编号已在 D3 开始：`AGENTS.md` 与 `docs/architecture.md` 第 3 节的硬条款已全部编号，
设计文档里编号的是各自最承重的几条。其余仍是无 ID 的散文，遇到就地补号，号段按本节的受控词表取。

## 5. STATUS.md 的列与取值

[STATUS.md](STATUS.md) 是瞬时状态的唯一承载。它是一张表，一行一个工作项。C 类设计文档不再承载
`implemented` / `pending` / `passed` 这类状态。

| 列 | 取值 |
| --- | --- |
| 工作项 | 自由文本，短名 |
| 条款 | 该工作项影响的 `BCA-*` 或 `APP-MEMO-*` ID 列表；尚未编号时写 `未编号` |
| 决策 | `required` \| `optional` \| `rejected` |
| 设计 | `draft` \| `pending-review` \| `approved` \| `superseded` |
| 实施 | `not-started` \| `in-progress` \| `implemented` \| `reverted` |
| 验证 | `not-run` \| `static-audit-passed` \| `targeted-passed` \| `full-suite-passed` \| `simulator-passed` \| `device-passed` \| `failed` |
| 检查点 | 单个 commit 短哈希 |
| 更新日期 | `YYYY-MM-DD` |

- `BCA-DOC-004` 每格恰好一个值。禁止用 `/` 拼接多值，禁止自造状态词。
- `BCA-DOC-005` 一个工作项同时存在多种验证事实时，必须拆成多行工作项，而不是拼接一格。
- `BCA-DOC-006` 旧值不在 `STATUS.md` 中保留。每次变更把被覆盖的行追加到
  [history/status-log.md](history/status-log.md)，格式为「日期 + 工作项 + 旧值 → 新值 + 原因」。

验证列比 fwq 多 `simulator-passed` 与 `device-passed` 两档，少 `fresh-passed` 与 `regression-passed`：
App 侧的验证事实主要分「离线测试通过」「模拟器走通」「真机验收通过」三级，而模拟器通过**不等于**真机通过
（`APP-MEMO-016` 就是同一条规则在引擎、模拟器、真机上给出三个不同张数的实例）。把这两档合进 `full-suite-passed`
会让「待真机」这个最常见的挂起状态无法表达。

### 5.1 状态段落的三分法

- `BCA-DOC-007` 把状态从 C 类文档搬出时，必须逐句分流为三个去向，不得整段搬移：

  | 句子性质 | 去向 | 判定 |
  | --- | --- | --- |
  | 可归约为第 5 节枚举的状态 | `STATUS.md` 表格行 | 决策/设计/实施/验证/检查点 |
  | 叙事事实（某日跑了什么、拿到什么结果、哪次提交做了什么） | `history/status-log.md` | 过去时、带日期或哈希 |
  | 仍然有效的约束或范围声明 | 留在原 C 类文档 | 含 `必须` / `不得` / `禁止` / `不允许`，或声明影响范围与复用关系 |

- `BCA-DOC-008` 三分的验收方式不是「纯移动」，而是**字节守恒**：三个去向新增的字节之和，
  加上留在原处的字节，等于原段落字节。分流过程不得改写任何句子，只允许整句搬移。

## 6. 按任务读取

第一次接触本仓库的阅读顺序：本文 → [architecture.md](architecture.md) 第 1–3 节（模块、层、被脚本执行的不变量）
→ 改到哪一层再读对应的设计文档。

### 通用边界

- 模块划分、层与依赖方向、被 `scripts/check-architecture-boundaries.sh` 执行的不变量、并发、持久化、测试、构建：[architecture.md](architecture.md)
- 维护脚本的用途与用法：[../scripts/README.md](../scripts/README.md)
- 会话纪律、SwiftSoup 与 Readium 边界、规则执行边界：[../AGENTS.md](../AGENTS.md)

### 按领域

- 身份归属与数据库策略、CloudKit 作用域：[design/AccountScopedDatabaseMigration-Memo.md](design/AccountScopedDatabaseMigration-Memo.md)
- 读书 kind 的 App 侧接线（五仓改动、Readium 装配、章节与分页）：[design/Book-Kind-Wiring-Design.md](design/Book-Kind-Wiring-Design.md)
- 本地书籍导入与阅读器（入口已藏，代码由站点书复用）：[design/Local-Book-Import-Design.md](design/Local-Book-Import-Design.md)
- 规则目录：已添加来源的更新入口：[design/Catalog-Rule-Update-Design.md](design/Catalog-Rule-Update-Design.md)
- 规则目录：同站多条来源的副标题：[design/Catalog-Same-Site-Entry-Subtitle-Design.md](design/Catalog-Same-Site-Entry-Subtitle-Design.md)
- 运行期广告过滤承接规则匹配结果：[design/RuntimeAdFilter-Design.md](design/RuntimeAdFilter-Design.md)

`design/Book-Kind-Wiring-Design.md`、`design/Local-Book-Import-Design.md` 与 `design/RuntimeAdFilter-Design.md`
当前仍混装了合同与批次记录，拆分属 D3。读它们时以现在时陈述的章节为合同，带日期的落地/倒查章节按 H 类看待。

## 7. 归档索引

| 文档 | 内容 |
| --- | --- |
| [history/status-log.md](history/status-log.md) | 状态变更流水：被 STATUS.md 覆盖的旧值，与三分法从 C 类搬出的叙事事实 |
| [history/2026-09-19-docs-architecture-audit.md](history/2026-09-19-docs-architecture-audit.md) | 本文档架构的审计与迁移提案，含迁移前的量化基线 |
| [history/2026-09-18-code-audit.md](history/2026-09-18-code-audit.md) | 五仓代码审计：警告清单、架构、性能热点与逐项修正纪事 |
| [history/RSS-Removal.md](history/RSS-Removal.md) | RSS 从 App 五仓整体下线的执行记录与保留清单 |
| [history/Readium-Integration-Handoff.md](history/Readium-Integration-Handoff.md) | Readium 选型与 SwiftSoup fork 的来龙去脉（推进顺序已由 book 接线执行完） |
| [history/JablePlaybackRule-Handoff.md](history/JablePlaybackRule-Handoff.md) | jable.tv M3U8 抽取失败的根因交接（结论已由 fwq `BC-PLAYBACK-049` 承接） |
| [history/Phase0-Data-Contract-and-Security-Audit.md](history/Phase0-Data-Contract-and-Security-Audit.md) | CloudKit 阶段 0 的数据合同与 payload 安全审计（身份部分已失效，见其文首注） |

## 8. 迁移对照表

2026-09-19 的 D1 阶段把文档从 `Documentation/` 迁入 `docs/`，只移动、未改写。外部文档（含 fwq 仓库的只读归档）
里的旧路径按下表换算：

| 迁移前 | 迁移后 |
| --- | --- |
| `Documentation/Audit/2026-09-18-code-audit.md` | `docs/history/2026-09-18-code-audit.md` |
| `Documentation/Audit/2026-09-19-docs-architecture-audit.md` | `docs/history/2026-09-19-docs-architecture-audit.md` |
| `Documentation/Book/Book-Kind-Wiring-Design.md` | `docs/design/Book-Kind-Wiring-Design.md` |
| `Documentation/Book/Local-Book-Import-Design.md` | `docs/design/Local-Book-Import-Design.md` |
| `Documentation/Book/Readium-Integration-Handoff.md` | `docs/history/Readium-Integration-Handoff.md` |
| `Documentation/CloudKit/AccountScopedDatabaseMigration-Memo.md` | `docs/design/AccountScopedDatabaseMigration-Memo.md` |
| `Documentation/CloudKit/Phase0-Data-Contract-and-Security-Audit.md` | `docs/history/Phase0-Data-Contract-and-Security-Audit.md` |
| `Documentation/Sources/Catalog-Rule-Update-Design.md` | `docs/design/Catalog-Rule-Update-Design.md` |
| `Documentation/Sources/Catalog-Same-Site-Entry-Subtitle-Design.md` | `docs/design/Catalog-Same-Site-Entry-Subtitle-Design.md` |
| `Documentation/Sources/RSS-Removal.md` | `docs/history/RSS-Removal.md` |
| `Documentation/Video/JablePlaybackRule-Handoff.md` | `docs/history/JablePlaybackRule-Handoff.md` |
| `Documentation/Video/RuntimeAdFilter-Design.md` | `docs/design/RuntimeAdFilter-Design.md` |

本仓库内引用这些路径的 Swift 注释已同步更新。fwq 仓库 `docs/history/` 的归档按只读归档处理，一行未改——
那里出现的旧路径查本表。fwq `docs/rules/` 的两份 C 类文档与 `docs/rules/STATUS.md` 里也有旧路径，是否同步更正待裁决。
