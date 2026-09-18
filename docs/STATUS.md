# 实施状态

本文是瞬时状态的唯一承载，形态与取值由 [文档索引](README.md) 第 5 节定义。
C 类设计文档不再承载 `implemented` / `pending` / `passed` 这类状态。

每格恰好一个值（`BCA-DOC-004`）。一个工作项同时存在多种验证事实时拆成多行（`BCA-DOC-005`）。
被覆盖的旧值追加到 [history/status-log.md](history/status-log.md)（`BCA-DOC-006`）。

条款列写 `未编号` 的行，是条款编号（D3）尚未执行的结果，不是「没有约束」。

## 0. 读这张表的纪律

**本表的行不会随条款落地自动退休。** 开工前的三步核对（都是零成本）：在 `BrowseCraft/` 与四个包里
grep 该行点名的类型或文件，看有没有实现；在本表里交叉查同一工作项有没有别的行标了 `implemented`；
该项若有产物可查（真机日志、模拟器截图、测试产物），按产物时间线看症状还在不在。

并且要看全五个状态列——`设计` 列为 `superseded` 就说明该设计已被取代，此时 `实施=not-started`
是正确的记法而不是过期。

`验证` 列的三级不可互相推断：`full-suite-passed` 是离线测试全过，`simulator-passed` 是模拟器上
人工走通了流程，`device-passed` 是用户在真机上确认。模拟器通过**不等于**真机通过。

## 1. 读书 kind（book）

| 工作项 | 条款 | 决策 | 设计 | 实施 | 验证 | 检查点 | 更新日期 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 读书 kind App 侧接线立项（三批范围、五仓改动清单、目录接口封闭枚举的兼容硬约束与发布策略） | `BC-BOOK-001` `BC-BOOK-012` | required | approved | implemented | full-suite-passed | 7ae4270 | 2026-09-13 |
| 批次 A：APIKit / Core / Domain 的 book 枚举与 `BookSiteRuleValidator`、各分流点补 book | `BC-BOOK-001` | required | approved | implemented | full-suite-passed | 43dfef2 | 2026-09-14 |
| 批次 B：Runtime 按规则取正文与音频、RWPM 装配、Readium 出版物构建 | `BC-BOOK-012` | required | approved | implemented | full-suite-passed | ac37e7f | 2026-09-14 |
| 批次 C：添加来源入口、站点书详情、共用 EPUB 阅读器、`SiteBookIdentity` 与迁移 v4 | `BC-BOOK-012` | required | approved | implemented | full-suite-passed | 8b280ff | 2026-09-14 |
| 站点书整链（sfacg 添加 → 列表 → 作品 → 章节 → 正文 → 续读） | `BC-BOOK-012` | required | approved | implemented | device-passed | 9b3a7d8 | 2026-09-15 |
| 站点有声作品的播放器（AudioNavigator 内核、远程 mp3 经 HTTPContainer、锁屏控制） | `BC-BOOK-012` | required | approved | implemented | simulator-passed | 11821b6 | 2026-09-14 |
| 站点书搜索：由规则声明，与漫画 / 影视同一条合同 | `BC-SEARCH-004` | required | approved | implemented | full-suite-passed | 84af71b | 2026-09-15 |
| 站点书进 History 页：与漫画、视频同列 | 未编号 | required | approved | implemented | full-suite-passed | 79512a9 | 2026-09-16 |
| book catalog 不发布进公共目录——2026-09-14 用户裁决发布 biquhua 后被取代，当前靠服务器 `kinds` 缺省不回 book | `BC-BOOK-001` | rejected | superseded | reverted | not-run | 43dfef2 | 2026-09-14 |
| 四个接口变体（list / detail / reader 的 API 形态）——无语料，另立项 | `BC-BOOK-012` | optional | draft | not-started | not-run | 8b280ff | 2026-09-14 |
| 本地书籍导入 B0：Domain 模型、三个仓储协议、六用例、迁移 v3 与边界脚本禁 Readium | 未编号 | required | approved | implemented | full-suite-passed | 4811cb1 | 2026-09-13 |
| 本地书籍导入 B1：Readium 环境 / 嗅探器 / 打开器、容器内文件存储、三个 GRDB Record 与仓储 | 未编号 | required | approved | implemented | full-suite-passed | 8a5b8a9 | 2026-09-13 |
| 本地书籍导入 B2：书架与 EPUB 阅读器、目录跳转、书签、退出重开续读 | 未编号 | required | approved | implemented | simulator-passed | 1c78bb2 | 2026-09-14 |
| 本地书籍导入 B3：有声书播放器——按「入口不对用户暴露」的裁决不做 | 未编号 | rejected | superseded | not-started | not-run | 1c78bb2 | 2026-09-14 |
| 本地导入入口已藏：去掉 Library 工具栏「书籍」与 RootView 书架装配，代码留给站点抓取路复用 | 未编号 | required | approved | implemented | full-suite-passed | 1c78bb2 | 2026-09-14 |
| Readium Swift Toolkit 3.11.0 选型与 SwiftSoup fork 覆盖 | 未编号 | required | approved | implemented | full-suite-passed | 7ad2704 | 2026-09-13 |
| PDF 与 CBZ 不接（PDF 见 `BC-BOOK-012`，CBZ 漫画线保持自研阅读器） | `BC-BOOK-012` | rejected | approved | not-started | not-run | f443602 | 2026-09-13 |

## 2. 规则目录

| 工作项 | 条款 | 决策 | 设计 | 实施 | 验证 | 检查点 | 更新日期 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 已添加来源的「更新规则」入口 | 未编号 | required | approved | implemented | full-suite-passed | a8a9d5b | 2026-09-14 |
| 目录刷新时静默覆盖本地规则——先给显式入口，量到需求再考虑自动 | 未编号 | rejected | approved | not-started | not-run | a8a9d5b | 2026-09-14 |
| 同站多条来源的副标题显示各自入口地址 | 未编号 | required | approved | implemented | device-passed | 1513a0f | 2026-09-15 |

## 3. 影视线运行期

| 工作项 | 条款 | 决策 | 设计 | 实施 | 验证 | 检查点 | 更新日期 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 运行期广告过滤承接规则匹配结果（App 侧对规则匹配到的候选执行过滤） | `APP-MEMO-008` | required | approved | implemented | full-suite-passed | ff58d6a | 2026-08-29 |
| jable.tv M3U8 播放规则的抽取根因（结论已由 fwq `BC-PLAYBACK-049` 承接） | `BC-PLAYBACK-049` | required | superseded | not-started | not-run | 4a3814b | 2026-08-21 |

## 4. 身份与同步

| 工作项 | 条款 | 决策 | 设计 | 实施 | 验证 | 检查点 | 更新日期 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 身份边界切换到 Sign in with Apple 与后端生成的 AppUser UUID | 未编号 | required | approved | implemented | full-suite-passed | eeb288e | 2026-07-28 |
| CloudKit 上传前的安全门禁（Header 拦截、非 Header 路径检查、记录大小预算） | 未编号 | required | approved | not-started | not-run | 3ab9d73 | 2026-07-22 |
| RSS 整体下线：删功能、迁移 v6 清存量、同步跳过 rss、书籍收藏改记 book | 未编号 | required | approved | implemented | full-suite-passed | f263274 | 2026-09-16 |

## 5. 文档架构迁移

| 工作项 | 条款 | 决策 | 设计 | 实施 | 验证 | 检查点 | 更新日期 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| D0 冻结基线：现状量化、逐份 C/S/H/E 判定、五处 RSS 漂移 | `BCA-DOC-001` | required | approved | implemented | static-audit-passed | 2ce6b99 | 2026-09-19 |
| D1 建索引 + 只移动文件：12 份迁入 `docs/`，新建索引，修五处 RSS 漂移 | `BCA-DOC-002` `BCA-DOC-003` | required | approved | implemented | static-audit-passed | 2ce6b99 | 2026-09-19 |
| D2 状态出设计文档：四份 C 类的状态头与两处验证节按三分法分流 | `BCA-DOC-007` `BCA-DOC-008` | required | approved | implemented | static-audit-passed | 812fde5 | 2026-09-19 |
| D3 条款编号与混装拆分：分配 `BCA-*` ID，fwq 已定义的改引用点，拆混装文档 | `BCA-DOC-001` `BCA-DOC-002` | required | approved | implemented | static-audit-passed | 812fde5 | 2026-09-19 |
| fwq 的 `protectedResource` 与 `executionPolicy` 两条约束只有正文没有稳定 ID，本仓库只能按文档引用——是否请 fwq 分配 ID | `BCA-DOC-001` | optional | draft | not-started | not-run | 812fde5 | 2026-09-19 |
| C 类里的散文硬条款一次扫完编号：逐行分类后确认真条款 22 条，其余是描述句、章节标题与已编号条款的续行 | `BCA-DOC-002` | required | approved | implemented | static-audit-passed | c0a72fe | 2026-09-19 |
| D4 机器闸门 `scripts/check-docs.py`：A1–A10 十项，每项经反向植入验证会红 | `BCA-DOC-010` | required | approved | implemented | targeted-passed | a330927 | 2026-09-19 |
| D5 `HANDOFF.md` 会话入口：四样内容，只记现查口径不记数字，只记纯 App 侧的工作 | `BCA-DOC-011` | required | approved | implemented | targeted-passed | a2adece | 2026-09-19 |
| 2026-09-18 代码审计第 5 节修正清单的逐条状态尚未归到本表——要判断还剩什么必须读原文 | 未编号 | optional | draft | not-started | not-run | a2adece | 2026-09-19 |
| fwq 可写文件里指向 App 文档的九处旧路径已更正；`docs/history/` 十一处按只读归档未动，查迁移对照表 | 未编号 | required | approved | implemented | static-audit-passed | 4fd6087 | 2026-09-19 |
| `BrowseCraftCore` 文档迁移：十份进 `docs/design` 与 `docs/history`，建索引，三份混装按节三分 | `BCA-DOC-009` | required | approved | implemented | static-audit-passed | 69233d1 | 2026-09-19 |
| Core 预检合同仍在描述 v3 裁决已删除的一跳采样与 family coverage（`VideoGenerationOneHopPlanner` / `DefaultSourceListFamilyAssessor`）——正文待过一遍 | 未编号 | required | draft | not-started | not-run | 69233d1 | 2026-09-19 |
| A10 文档点名的代码符号必须存在（fwq `BC-DOC-028` 那类）：白名单只许收敛，识别家族通配与路径段 | `BCA-DOC-014` | required | approved | implemented | targeted-passed | 15394c2 | 2026-09-19 |
| `scripts/update-rules-package.sh` 指向的 `BrowseCraftRulesKit` 不在当前五仓布局里——脚本是否已死待核 | 未编号 | optional | draft | not-started | not-run | 09d2af1 | 2026-09-19 |
| `BookBookmarksSheet` 是本地导入设计里未实现的计划名——入口已藏，该节是未建代码的设计留档 | 未编号 | optional | approved | not-started | not-run | 09d2af1 | 2026-09-19 |
